# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = ["sentence-transformers==3.3.1", "torch==2.5.1"]
# ///
"""Sense-ranking quality eval against real Wiktionary entries.

Mirrors the scoring scheme in Fathom/Domain/SenseRanking/EmbeddingSenseRanker.swift:
gloss + up to 3 example/quote docs, anchor discount λ=0.25, example scores
averaged with the definition score, soft PoS penalty ×0.94.

Usage: uv run eval_senses.py [model_id]     (default: thenlper/gte-base)
Baselines measured 2026-07: bge-small-en-v1.5 = 13/20, gte-base = 17/20.
"""
import json
import sys
from pathlib import Path

from sentence_transformers import SentenceTransformer

HERE = Path(__file__).parent
exec(open(HERE / "eval_cases.py").read())  # CASES, flatten, pos_matches

ANCHOR_LAMBDA = 0.25
POS_PENALTY = 0.94

model_id = sys.argv[1] if len(sys.argv) > 1 else "thenlper/gte-base"
model = SentenceTransformer(model_id)
_cache = {}


def embed(t):
    if t not in _cache:
        _cache[t] = model.encode([t], normalize_embeddings=True)[0]
    return _cache[t]


correct = 0
for word, surface, gold_pos, sentence, expected in CASES:
    senses = flatten(json.load(open(HERE / f"dict_{word}.json")))
    ctx, anchor = embed(sentence), embed(word)

    def disc(vec):
        return float(ctx @ vec) - ANCHOR_LAMBDA * float(anchor @ vec)

    scored = []
    for pos, definition, examples, quotes in senses:
        def_score = disc(embed(f"{word} ({pos}): {definition}"))
        score = def_score
        for t in (examples + quotes)[:3]:
            score = max(score, (def_score + disc(embed(t))) / 2)
        if not pos_matches(gold_pos, pos):
            score *= POS_PENALTY
        scored.append((score, definition))
    scored.sort(reverse=True)
    ok = expected.lower() in scored[0][1].lower()
    correct += ok
    mark = "✓" if ok else "✗"
    print(f"{mark} {surface:9s} “{sentence[:46]}…” → {scored[0][1][:60]}")

print(f"\n{model_id}: {correct}/{len(CASES)}")
