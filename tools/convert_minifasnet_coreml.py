#!/usr/bin/env python3
"""
Convert MiniFASNet ONNX (Silent-Face-Anti-Spoofing) to Core ML for Glance.

Requires:
  pip install coremltools onnx onnxruntime

Download ONNX first, e.g. from:
  https://github.com/QingHeYang/Silent-Face-Anti-Spoofing-onnx

Usage:
  python3 tools/convert_minifasnet_coreml.py \\
      --onnx path/to/2.7_80x80_MiniFASNetV2.onnx \\
      --out glance/Models/MiniFASNetV2.mlpackage
"""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--onnx", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    try:
        import coremltools as ct
    except ImportError as exc:
        raise SystemExit(
            "coremltools not installed. pip install coremltools onnx"
        ) from exc

    if not args.onnx.exists():
        raise SystemExit(f"Missing ONNX model: {args.onnx}")

    model = ct.converters.onnx.convert(
        model=str(args.onnx),
        minimum_deployment_target=ct.target.macOS13,
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(args.out))
    print(f"Wrote {args.out}")
    print("Next: add a MiniFASNetPAD Swift wrapper mirroring ArcFaceEmbedder,")
    print("and feed its spoof probability into LivenessCues as a deny cue.")


if __name__ == "__main__":
    main()
