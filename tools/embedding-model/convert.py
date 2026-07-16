# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#     "torch==2.5.1",
#     "transformers==4.36.2",
#     "coremltools==8.3.0",
#     "numpy",
# ]
# ///
"""Convert thenlper/gte-base to a Core ML mlpackage for on-device
sense ranking in Fathom.

The exported model bakes in attention-mask-aware mean pooling and L2
normalization, so the Swift side only feeds token ids + mask and reads a
unit-length 768-dim sentence embedding.

Outputs (relative to repo root):
  Fathom/Resources/SenseEmbedding.mlpackage   int8-quantized model
  Fathom/Resources/bge_vocab.txt              WordPiece vocabulary
  FathomTests/Fixtures/tokenizer_fixtures.json  tokenizer parity fixtures
"""

import json
import shutil
import sys
from pathlib import Path

import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

MODEL_ID = "thenlper/gte-base"
SEQ_LEN = 128
REPO_ROOT = Path(__file__).resolve().parents[2]
RESOURCES = REPO_ROOT / "Fathom" / "Resources"
FIXTURES_DIR = REPO_ROOT / "FathomTests" / "Fixtures"
MLPACKAGE_PATH = RESOURCES / "SenseEmbedding.mlpackage"

TEST_SENTENCES = [
    "The bank raised interest rates again this quarter.",
    "They had a picnic on the bank of the river.",
    "A financial institution that accepts deposits and makes loans.",
    "The land alongside or sloping down to a river or lake.",
    "He tried to steer the conversation toward safer ground.",
    "The bat flew out of the cave at dusk.",
    "She swung the bat and hit a home run.",
    "word: a single distinct meaningful element of speech or writing.",
]


class PooledEncoder(torch.nn.Module):
    """BGE encoder + masked mean pooling + L2 normalization."""

    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model
        # Pass position/token-type ids explicitly: letting BertEmbeddings
        # derive them from the input shape emits an aten::Int on an array
        # constant that the coremltools frontend rejects.
        self.register_buffer(
            "position_ids", torch.arange(SEQ_LEN, dtype=torch.int64).unsqueeze(0)
        )
        self.register_buffer(
            "token_type_ids", torch.zeros((1, SEQ_LEN), dtype=torch.int64)
        )

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor):
        # Run embeddings + encoder manually so we control the additive
        # attention mask: BertModel uses -3.4e38, which overflows to -inf/NaN
        # when Core ML runs the graph in fp16. -30000 is fp16-safe and still
        # zeroes masked positions after softmax.
        embedded = self.model.embeddings(
            input_ids=input_ids,
            token_type_ids=self.token_type_ids,
            position_ids=self.position_ids,
        )
        additive_mask = (1.0 - attention_mask[:, None, None, :].to(embedded.dtype)) * -30000.0
        hidden = self.model.encoder(embedded, attention_mask=additive_mask)[0]  # [1, L, 768]
        mask = attention_mask.unsqueeze(-1).to(hidden.dtype)  # [1, L, 1]
        summed = (hidden * mask).sum(dim=1)
        counts = mask.sum(dim=1).clamp(min=1e-9)
        pooled = summed / counts
        return torch.nn.functional.normalize(pooled, p=2, dim=1)


def torch_embed(wrapper, tokenizer, texts):
    out = []
    for text in texts:
        enc = tokenizer(
            text,
            padding="max_length",
            truncation=True,
            max_length=SEQ_LEN,
            return_tensors="pt",
        )
        with torch.no_grad():
            vec = wrapper(enc["input_ids"], enc["attention_mask"])
        out.append(vec[0].numpy())
    return np.stack(out)


def coreml_embed(mlmodel, tokenizer, texts):
    out = []
    for text in texts:
        enc = tokenizer(
            text,
            padding="max_length",
            truncation=True,
            max_length=SEQ_LEN,
            return_tensors="np",
        )
        pred = mlmodel.predict(
            {
                "input_ids": enc["input_ids"].astype(np.int32),
                "attention_mask": enc["attention_mask"].astype(np.int32),
            }
        )
        out.append(pred["embedding"][0])
    return np.stack(out)


def report_parity(label, ref, test):
    sims = [
        float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))
        for a, b in zip(ref, test)
    ]
    print(f"  {label}: cosine parity min={min(sims):.6f} mean={np.mean(sims):.6f}")
    return min(sims)


def main():
    import coremltools as ct

    print(f"Loading {MODEL_ID} ...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    # eager attention: the SDPA path emits int() casts torch.jit.trace can't
    # represent, which breaks the coremltools frontend.
    model = AutoModel.from_pretrained(
        MODEL_ID, torchscript=True, attn_implementation="eager"
    ).eval()
    wrapper = PooledEncoder(model).eval()

    print("Computing PyTorch reference embeddings ...")
    ref = torch_embed(wrapper, tokenizer, TEST_SENTENCES)

    print("Tracing ...")
    example_ids = torch.ones((1, SEQ_LEN), dtype=torch.int64)
    example_mask = torch.ones((1, SEQ_LEN), dtype=torch.int64)
    traced = torch.jit.trace(wrapper, (example_ids, example_mask))

    print("Converting to Core ML (mlprogram, fp16) ...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, SEQ_LEN), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, SEQ_LEN), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.short_description = (
        "gte-base sentence encoder (mean-pooled, L2-normalized)"
    )
    mlmodel.author = "Converted from thenlper/gte-base (MIT license)"

    print("Verifying fp16 parity ...")
    fp16_min = report_parity("fp16", ref, coreml_embed(mlmodel, tokenizer, TEST_SENTENCES))

    print("Quantizing weights to int8 ...")
    from coremltools.optimize.coreml import (
        OpLinearQuantizerConfig,
        OptimizationConfig,
        linear_quantize_weights,
    )

    quant_config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")
    )
    mlmodel_int8 = linear_quantize_weights(mlmodel, config=quant_config)

    print("Verifying int8 parity ...")
    int8_min = report_parity(
        "int8", ref, coreml_embed(mlmodel_int8, tokenizer, TEST_SENTENCES)
    )

    if fp16_min < 0.999 or int8_min < 0.98:
        print("PARITY CHECK FAILED — not saving model", file=sys.stderr)
        sys.exit(1)

    RESOURCES.mkdir(parents=True, exist_ok=True)
    if MLPACKAGE_PATH.exists():
        shutil.rmtree(MLPACKAGE_PATH)
    mlmodel_int8.save(str(MLPACKAGE_PATH))
    size_mb = sum(f.stat().st_size for f in MLPACKAGE_PATH.rglob("*") if f.is_file()) / 1e6
    print(f"Saved {MLPACKAGE_PATH} ({size_mb:.1f} MB)")

    # Vocabulary for the Swift tokenizer.
    vocab = tokenizer.get_vocab()
    vocab_path = RESOURCES / "bge_vocab.txt"
    with open(vocab_path, "w") as f:
        for token, _ in sorted(vocab.items(), key=lambda kv: kv[1]):
            f.write(token + "\n")
    print(f"Saved {vocab_path} ({vocab_path.stat().st_size / 1e3:.0f} KB)")

    # Tokenizer parity fixtures for Swift unit tests.
    fixture_texts = TEST_SENTENCES + [
        "It's a well-known fact — naïve café-goers can't resist crème brûlée!",
        "Ephemeral: lasting for a very short time.",
        "bank (noun): the land alongside a river; e.g. \"We fished from the bank.\"",
        "supercalifragilisticexpialidocious antidisestablishmentarianism",
        "  Multiple   spaces\tand\nnewlines  ",
        "UPPERCASE and MixedCase Words",
        "",
    ]
    fixtures = []
    for text in fixture_texts:
        enc = tokenizer(
            text, padding="max_length", truncation=True, max_length=SEQ_LEN
        )
        fixtures.append(
            {
                "text": text,
                "input_ids": enc["input_ids"],
                "attention_mask": enc["attention_mask"],
            }
        )
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    fixtures_path = FIXTURES_DIR / "tokenizer_fixtures.json"
    with open(fixtures_path, "w") as f:
        json.dump({"seq_len": SEQ_LEN, "cases": fixtures}, f, indent=1)
    print(f"Saved {fixtures_path}")

    print("Done.")


if __name__ == "__main__":
    main()
