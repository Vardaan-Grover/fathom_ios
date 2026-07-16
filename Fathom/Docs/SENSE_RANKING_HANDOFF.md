# Contextual Definition Selection — Engineering Handoff

Last updated: 2026-07-12. Status: **working, verified by tests, NOT yet production-hardened**.
This document is self-contained: it describes the feature, every design decision and the
measurements behind it, every non-obvious bug already hit and fixed, and the known gaps.
An agent should be able to rebuild the system from scratch or tweak it from this file alone.

---

## 1. What the feature does

When a reader selects a word in the EPUB reader (Readium) and taps **Define**, the
vocabulary sheet opens with the full dictionary entry (from
`https://freedictionaryapi.com/api/v1/entries/en/<word>`, Wiktionary-backed). Because most
words have many senses (Wiktionary "bank" ≈ 40, "spring" ≈ 60 incl. subsenses), the app
ranks all senses against **the sentence the word was selected in** and shows the best one
in a "In this context" card at the top of the sheet. Ranking runs automatically on sheet
open, fully on-device, offline.

Latency budget agreed with the owner: **1–2 s acceptable**; measured warm re-rank is
~120 ms on the iOS simulator (gte-base). English only by design — other languages just show
the unranked list.

## 2. Architecture (current)

```
ReadiumNavigatorView (selection)                     Fathom/ReaderEngine/ReadiumNavigatorView.swift
  └─ SentenceContextExtractor.extract(before:selection:after:)
        → SentenceContext { sentence, wordRange }    Fathom/Domain/SenseRanking/SentenceContextExtractor.swift
  └─ onDefine(text, locatorJSON, SentenceContext?)   threaded through NavigatorCommands
ReaderScreen                                          Fathom/UI/Reader/ReaderScreen.swift
  └─ VocabularySheetViewModel(word:…, sentenceContext:)  Fathom/Presentation/VocabularySheetViewModel.swift
        init → fetchDefinition() → rankContextually()   (automatic; no user action)
  └─ SenseRanker protocol                             Fathom/Domain/SenseRanking/SenseRanker.swift
        └─ EmbeddingSenseRanker (actor, singleton)    Fathom/Domain/SenseRanking/EmbeddingSenseRanker.swift
              ├─ WordPieceTokenizer                   Fathom/Domain/SenseRanking/WordPieceTokenizer.swift
              ├─ SenseEmbedding.mlmodelc              from Fathom/Resources/SenseEmbedding.mlpackage
              └─ bge_vocab.txt                        Fathom/Resources/bge_vocab.txt (BERT uncased vocab, 30522)
VocabularySheetView                                   Fathom/UI/Vocabulary/VocabularySheetView.swift
  └─ contextualCard: shimmer while isRanking, card when ranked
```

- `SenseRanker` is a deliberate seam: alternative rankers (LLM, cross-encoder, server) can
  be added without touching the view model or UI. `SenseRankingRequest` carries
  `word` (headword), `surfaceWord` (exact form in text), `sentence`, `wordRange`
  (exact `Range<String.Index>` of the selection in the sentence), and the decoded
  `DictionaryWordEntry`.
- The model is **prewarmed** in `ReaderScreen.setupOnAppear()` via
  `Task.detached { await EmbeddingSenseRanker.shared.prewarm() }` so the first lookup
  doesn't pay cold-start.
- The old implementation (`Fathom/Domain/ContextualRanker.swift`, based on Apple's
  `NLContextualEmbedding`) was deleted. Its failure modes are listed in §7 so nobody
  reintroduces them.

## 3. Model

**`thenlper/gte-base`** (109M params, 768-dim, BERT architecture, bert-base-uncased
WordPiece vocab), converted to a Core ML mlprogram:

- `Fathom/Resources/SenseEmbedding.mlpackage` — int8 weights, **109.2 MB**,
  fixed shape `[1, 128]` int32 `input_ids` + `attention_mask`, output `embedding` `[1, 768]`.
- Attention-mask-aware **mean pooling and L2 normalization are baked into the graph** —
  Swift feeds token ids and reads a unit vector; cosine similarity = dot product.
- Conversion parity vs PyTorch (cosine on 8 test sentences): fp16 ≥ 0.999999, int8 ≥ 0.9993.

History: shipped first with `BAAI/bge-small-en-v1.5` (33.5 MB, 384-dim); replaced after a
real-world miss (§6). If app size ever forces a downgrade, bge-small scores 13/20 on the
eval below; gte-small is 14/20 and NOT worth the switch.

### 3.1 Conversion pipeline

`tools/embedding-model/convert.py` — PEP-723 uv script (`uv run convert.py`).
Pinned: `torch==2.5.1`, `transformers==4.36.2`, `coremltools==8.3.0`. It downloads the
model, wraps it, traces, converts, quantizes, parity-checks (hard-fails below fp16 0.999 /
int8 0.98), and writes the mlpackage + vocab + tokenizer test fixtures.

**Conversion gotchas already solved — do not rediscover these:**

1. `torch.jit.trace` of HF `BertModel` emits an `aten::Int` on an array constant that the
   coremltools frontend rejects (`TypeError: only 0-dimensional arrays…`). Cause:
   `BertEmbeddings` deriving `position_ids`/`token_type_ids` from the input shape.
   Fix: register both as explicit `[1, SEQ_LEN]` buffers and pass them into the model.
2. `BertModel`'s additive attention mask uses `-3.4e38`, which overflows fp16 → embeddings
   are garbage (parity ~0.6) after fp16 conversion. Fix: run `model.embeddings` +
   `model.encoder` manually and build the mask as `(1 - mask) * -30000.0`.
3. Use `attn_implementation="eager"` when loading (SDPA path also emits untraceable casts).

### 3.2 Runtime gotcha (the worst one)

`MLModelConfiguration.computeUnits = .all` makes this model return **all-zero embeddings on
the iOS simulator** (GPU shim executes the graph and silently produces zeros; every sense
then ties and the first one wins). Production config is
**`.cpuAndNeuralEngine`** — correct everywhere, and the ANE is the fast path on device
anyway. If ranking ever returns the first sense for everything, check this first.

## 4. Tokenizer

`WordPieceTokenizer` (Swift, zero dependencies) replicates the HF BERT-uncased pipeline:
NFD lowercase + strip combining marks, whitespace/control cleanup, CJK spacing,
punctuation splitting, greedy longest-match WordPiece with `##` continuations,
`[CLS]/[SEP]` wrap, pad/truncate to 128.

Parity is pinned by `FathomTests/Fixtures/tokenizer_fixtures.json` (15 cases generated by
convert.py from the exact HF tokenizer) via `FathomTests/WordPieceTokenizerTests.swift` —
currently 15/15. **Any tokenizer change must keep this test green**; a silent mismatch
corrupts every embedding. gte-base and bge-small share the same vocab file
(`bge_vocab.txt` — name is historical).

## 5. Scoring scheme (empirically selected — see §6 for the data)

Per candidate sense (subsenses flattened into their own candidates):

```
glossDoc      = "<word> (<pos>): <definition>"
usageDocs     = first 3 of (sense.examples + sense.quotes[].text), each filtered:
                  10 < length < 160 chars AND no /\d{4}|letter to|page \d/  (citation junk)
disc(doc)     = cos(ctxVec, docVec) − 0.25 · cos(anchorVec, docVec)     // anchor discount
defScore      = disc(glossDoc)
similarity    = max(defScore, max over usage docs of (defScore + disc(usageDoc)) / 2)
if PoS(tagged in sentence via NLTagger) mismatches sense PoS: similarity ×= 0.94  // soft prior
probability   = softmax over candidates with temperature 0.05
isHighConfidence = (p1 − p2) ≥ 0.15
```

Where `ctxVec = embed(sentence)`, `anchorVec = embed(bare headword)`.

Why each piece exists:
- **Anchor discount (λ=0.25)**: kills "word-echo" glosses — short definitions like
  cramp → "That which confines or contracts." score high against *anything* containing the
  headword. Subtracting similarity-to-the-bare-word leaves only context-driven signal.
  λ=0.4+ over-discounts and tanks accuracy (10/20). Applies to gloss AND usage docs.
- **Averaging usage with definition** (not raw max): a single rogue literary quote
  ("Tiber trembled underneath her banks", sim 0.82 vs any bank sentence) otherwise flips
  the sense. Raw-max aggregation lost 2 cases.
- **Quote/citation filter**: Wiktionary quotes carry years/attributions that add noise.
- **Soft PoS penalty** (never a hard filter): NLTagger errs; hard filtering was a failure
  mode of the old implementation. 0.85 vs 0.94 made no difference on the eval; 0.94 kept.
- **Sense-embedding cache**: per headword (`senseCache`, FIFO, 40 words) — repeat lookups
  only embed the context sentence (~120 ms warm).

## 6. Evaluation — the numbers behind every decision

Harness: `tools/embedding-model/eval/eval_senses.py` (uv script) +
`eval_cases.py` (20 cases) + cached real API responses (`dict_*.json`). Run:
`cd tools/embedding-model/eval && uv run eval_senses.py [model_id]`.
It mirrors the Swift scheme exactly; PyTorch↔CoreML parity 0.999 means Python conclusions
transfer.

Cases: cramp×2 (incl. the real user miss "Presently I was seized with a cramp in my
stomach"), bank×2, bat×2, spring×3, chest×2, bar×3, vessel×2, company×2, seize×2 —
all against **full live Wiktionary entries** (12–60 senses each), gold PoS supplied.

| Approach | Strict acc | Verdict |
|---|---|---|
| bge-small, original scheme | 11–13/20 | shipped v1; user-visible misses |
| bge-small + every scheme variant tried | ≤13/20 | model ceiling, not scheme |
| gte-small | 14/20 | not worth a swap |
| ms-marco-MiniLM cross-encoder (22M) | 9/20 | relevance ≠ gloss match |
| stsb-TinyBERT cross-encoder | 9/20 | ditto |
| NLI cross-encoders (MiniLM2 / deberta-xsmall) | 4–5/20 | worst |
| Apple Foundation Models 3B, MCQ prompt | 10/20 | + **guardrail errors**: Wiktionary's vulgar slang senses (e.g. under "spring") make `LanguageModelSession` throw `guardrailViolation` for benign lookups. Also ~0.5–0.9 s/lookup. |
| all-mpnet-base-v2 (109M) | 11/20 | size ≠ quality |
| e5-base-v2 | 13/20 | |
| bge-base-en-v1.5 | 16/20 | cramp still wrong |
| **gte-base + anchor λ=0.25 (SHIPPED)** | **17/20** | cramp fixed; remaining misses near-ties |

Remaining 3 misses (all photo-finish, arguably acceptable senses):
- bank/loan → river bank (rogue quote effect, partially mitigated)
- "swung the bat" → "a player rated according to skill in batting" (adjacent)
- "admitted to the bar" → "the bar exam" (0.0001 gap vs "lawyers collectively")

Key negative results worth remembering: **off-the-shelf cross-encoders do not transfer to
gloss matching without WSD fine-tuning** (GlossBERT/BEM-style training is what makes them
win in the literature), and **the on-device LLM is disqualified by guardrails + zero-shot
accuracy**, not just latency.

## 7. Failure modes of the deleted v1 (do not reintroduce)

1. Context "sentence" was `locator.text.before + selection + after` concatenated raw —
   a window spanning sentence fragments, not a sentence.
2. Word located via `range(of: word, .caseInsensitive)` → first substring match, often in
   `before`-text or inside another word ("art" in "part"). The selection offset is *known*
   (selection sits exactly after `before`) — `SentenceContextExtractor` uses it.
3. `NLContextualEmbedding` token-vector vs mean-pooled gloss-vector comparison — an MLM
   embedding space never trained for similarity; scores compressed (confidence delta had
   to be 0.04), and token↔token vs token↔sentence scores were mixed in one `max()`.
4. Subsenses never scored; senses recomputed on every tap; ranking was manual (sparkles button).

## 8. Tests & verification

- `FathomTests/EmbeddingSenseRankerTests.swift` — end-to-end quality gate on the real
  Core ML model (app-hosted, `Bundle.main`): river/financial/aviation bank, cricket bat,
  subsense "run", **stomachCramp regression** (the exact user-reported sentence vs real
  Wiktionary senses), warm-latency budget (<2 s asserted; ~0.12 s measured).
- `FathomTests/WordPieceTokenizerTests.swift` — HF parity fixtures (see §4).
- `FathomTests/SentenceContextExtractorTests.swift` — sentence extraction: enclosing
  sentence from fragment windows, correct occurrence (not first match), whitespace
  collapse, degenerate no-punctuation clamping (≤320 chars), empty-selection nil.
- Run: `xcodebuild -project Fathom.xcodeproj -scheme Fathom -destination 'id=<sim-udid>' test`
  (scheme requires an iOS 26.x simulator). 36/36 green as of this writing.
- Xcode project note: `FathomTests` target originally had **no Resources build phase**;
  one was added (`FA7E57F1AA0000000000AFF1` in project.pbxproj) so fixtures reach the test
  bundle. pbxproj IDs must be unique — a collision "damages" the project (plutil won't
  catch it).

## 9. Known gaps — why this is not yet "production ready"

Ranked roughly by user impact:

1. **Eval is 20 cases.** Enough to pick between approaches; not enough to claim accuracy.
   Next agent: grow `eval_cases.py` (every future user-reported miss goes in), or build a
   bulk eval from a WSD corpus (SemCor/WSD-Eval mapped to Wiktionary senses is nontrivial
   but even 200 hand-checked cases would be decisive).
2. **Confidence gating is crude.** `p1 − p2 ≥ 0.15` on a softmax over 12–60 senses; with
   many senses probabilities flatten (user saw p=0.177 as "winner"). Options: gate on raw
   similarity margin instead; suppress the card entirely (or show "Possibly…" style) below
   a threshold tuned on the eval set; show top-2 senses when close.
3. **Ceiling: bi-encoder without WSD fine-tuning.** The known step-change is fine-tuning a
   small cross-encoder (GlossBERT recipe: SemCor + WordNet glosses, MiniLM-L6 base) used to
   rerank the bi-encoder's top-5. That's a training project (~GPU-hours) but the protocol
   seam and eval harness are already in place.
4. **Memory/jetsam**: the reader already fights jetsam on low-RAM devices (see project
   memory `reader-memory-jetsam`); a 109 MB int8 model is mmap'd (weights are clean pages)
   but prewarm-on-reader-open still raises pressure. Consider: prewarm on first Define
   instead; add an idle unload timer (`model = nil` after N minutes unused).
5. **"Alternative spelling/form of X" senses** ("draught" → "Alternative spelling of
   draft") rank meaninglessly — the real senses live under the other headword. The sheet
   already has an inflected-form banner for "past tense of X" patterns; extend that
   detection to alternative-spelling senses and/or auto-follow the redirect before ranking.
6. **Lemma mismatch**: for "banked" the glosses are built with headword "bank" but the
   dictionary API is queried with whatever the user selected; if the API 404s on an
   inflected form there is no automatic lemma retry (only the banner after a definition
   loads). Consider NLTagger `.lemma` fallback on 404.
7. **Cache key** is `word.lowercased() + "|" + entries.count` — same word with a changed
   entry payload (API update) collides. Hash the definitions instead if it ever matters.
8. **Repo hygiene**: the 109 MB mlpackage is committed to git (repo bloat; consider Git
   LFS or build-time download). `bge_vocab.txt` name is historical (it's generic BERT
   uncased vocab shared by both models).
9. **Multi-word selections** are not ranked (Define only appears for single words) —
   phrasal verbs/idioms ("give up", "at bat") are a gap.
10. **No telemetry**: no signal on real-world accuracy. Even a local "was this helpful"
    tap or counting how often users scroll past the card would close the loop.
11. **Highlight in the card** uses `range(of:)` on the surface word (first occurrence) for
    display only — `SentenceContext.wordRange` is available and should be used.
12. **Simulator-only latency numbers**; ANE-on-device performance not yet profiled
    (expect faster, but verify; also verify int8 + ANE numerics on hardware once).

## 10. How to make changes safely (checklist)

1. Scheme/model idea → prototype in `tools/embedding-model/eval/` (Python, minutes).
2. Beat 17/20 (or fix a target case without losing others) → port to
   `EmbeddingSenseRanker` — the Swift scheme must stay line-for-line equivalent to
   `eval_senses.py`.
3. New model → edit `MODEL_ID` in `convert.py`, run it (parity gate is built in). If the
   tokenizer family changes (non-BERT), regenerate fixtures AND update
   `WordPieceTokenizer` — fixture tests will catch drift.
4. `xcodebuild … test` — all suites, on an iOS 26 simulator.
5. Add any newly discovered real-world miss to BOTH `eval_cases.py` and
   `EmbeddingSenseRankerTests` (like `stomachCramp`).
6. Keep `computeUnits = .cpuAndNeuralEngine` (§3.2).
