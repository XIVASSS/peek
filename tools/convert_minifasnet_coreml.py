#!/usr/bin/env python3
"""Convert MiniFASNetV2 (Silent-Face-Anti-Spoofing) PyTorch weights to Core ML for Peek."""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument("--repo", type=Path, default=Path("/tmp/face-anti-spoofing"))
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    import coremltools as ct
    import torch

    sys.path.insert(0, str(args.repo))
    from models import MiniFASNetV2

    model = MiniFASNetV2()
    state = torch.load(args.weights, map_location="cpu", weights_only=True)
    if isinstance(state, dict) and "state_dict" in state:
        state = state["state_dict"]
    cleaned = {(k[7:] if k.startswith("module.") else k): v for k, v in state.items()}
    model.load_state_dict(cleaned, strict=True)
    model.eval()

    example = torch.rand(1, 3, 80, 80)
    traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input_image", shape=(1, 3, 80, 80))],
        outputs=[ct.TensorType(name="logits")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS13,
    )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    if args.out.exists():
        shutil.rmtree(args.out)
    mlmodel.save(str(args.out))
    print(f"Wrote {args.out}")
    desc = mlmodel.get_spec().description
    print("inputs:", [(i.name, i.type.WhichOneof("Type")) for i in desc.input])
    print("outputs:", [(o.name, o.type.WhichOneof("Type")) for o in desc.output])


if __name__ == "__main__":
    main()
