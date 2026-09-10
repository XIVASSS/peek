# Hardening tools

## Liveness selftest

See root `README.md` — validates deny/confirm latching after cue changes.

## MiniFASNet → Core ML

1. Clone or download ONNX weights from [Silent-Face-Anti-Spoofing-onnx](https://github.com/QingHeYang/Silent-Face-Anti-Spoofing-onnx).
2. `pip install coremltools onnx onnxruntime`
3. Run:

```bash
python3 tools/convert_minifasnet_coreml.py \
  --onnx /path/to/2.7_80x80_MiniFASNetV2.onnx \
  --out glance/Models/MiniFASNetV2.mlpackage
```

4. Implement `MiniFASNetPAD.swift` (mirror `ArcFaceEmbedder`), call from `LivenessFeatureExtractor`, map score into `passiveSpoof` or a dedicated deny cue.

The built-in `PassiveAntiSpoof` classical texture PAD ships without this step so the app builds offline.
