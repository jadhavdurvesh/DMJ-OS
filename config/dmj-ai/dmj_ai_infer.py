#!/usr/bin/env python3
"""
dmj_ai_infer.py

CPU inference wrapper for the Saudade v4 checkpoint, used by the `dmj-ai`
CLI command in DMJ OS.

This assumes the Saudade model class/config matches the architecture used
to train v4: 384 embed / 8 heads / 8 layers / 512 context, RoPE + RMSNorm +
SwiGLU. Adjust MODEL_KWARGS below if your repo's model class signature
differs — check github.com/jadhavdurvesh/microgpt_by_DMJ for the exact
class definition and swap the import in `load_model()`.

Usage:
    python3 dmj_ai_infer.py "your prompt here" [--max-tokens 200] [--temp 0.8]
"""
import argparse
import sys
import os

MODEL_DIR = os.environ.get("DMJ_AI_MODEL_DIR", "/opt/dmj-ai/model")
CHECKPOINT_PATH = os.path.join(MODEL_DIR, "saudade_v4.pt")
TOKENIZER_PATH = os.path.join(MODEL_DIR, "tokenizer_32k.json")

# Architecture used for the frozen Saudade v4 checkpoint.
MODEL_KWARGS = dict(
    n_embd=384,
    n_head=8,
    n_layer=8,
    block_size=512,
    vocab_size=32000,
)


def load_tokenizer():
    from tokenizers import Tokenizer
    if not os.path.exists(TOKENIZER_PATH):
        sys.exit(f"Tokenizer not found at {TOKENIZER_PATH}")
    return Tokenizer.from_file(TOKENIZER_PATH)


def load_model():
    import torch
    if not os.path.exists(CHECKPOINT_PATH):
        sys.exit(
            f"Checkpoint not found at {CHECKPOINT_PATH}.\n"
            "Bundle saudade_v4.pt into the OS image before building the ISO."
        )

    # --- IMPORTANT ---
    # Replace this import with the real Saudade model class from your repo,
    # e.g.:
    #   from saudade.model import SaudadeGPT
    # This placeholder defines a minimal stand-in so the script is runnable
    # out of the box; swap it for your actual architecture before shipping.
    try:
        from saudade_model import SaudadeGPT  # your repo's module, if vendored
    except ImportError:
        sys.exit(
            "Could not import SaudadeGPT. Vendor your model definition from "
            "github.com/jadhavdurvesh/microgpt_by_DMJ into /opt/dmj-ai/ as "
            "saudade_model.py (must expose a SaudadeGPT class matching the "
            "v4 architecture) and rebuild the ISO."
        )

    model = SaudadeGPT(**MODEL_KWARGS)
    state = torch.load(CHECKPOINT_PATH, map_location="cpu")
    state_dict = state.get("model_state_dict", state)
    model.load_state_dict(state_dict)
    model.eval()
    return model


def generate(prompt: str, max_tokens: int, temperature: float):
    import torch
    tok = load_tokenizer()
    model = load_model()

    ids = tok.encode(prompt).ids
    x = torch.tensor([ids], dtype=torch.long)

    with torch.no_grad():
        for _ in range(max_tokens):
            x_cond = x[:, -MODEL_KWARGS["block_size"]:]
            logits = model(x_cond)
            logits = logits[:, -1, :] / max(temperature, 1e-5)
            probs = torch.softmax(logits, dim=-1)
            next_id = torch.multinomial(probs, num_samples=1)
            x = torch.cat([x, next_id], dim=1)

    out_ids = x[0].tolist()
    return tok.decode(out_ids)


def main():
    parser = argparse.ArgumentParser(description="DMJ OS built-in AI (Saudade v4)")
    parser.add_argument("prompt", nargs="+", help="Prompt text")
    parser.add_argument("--max-tokens", type=int, default=200)
    parser.add_argument("--temp", type=float, default=0.8)
    args = parser.parse_args()

    prompt = " ".join(args.prompt)
    text = generate(prompt, args.max_tokens, args.temp)
    print(text)


if __name__ == "__main__":
    main()
