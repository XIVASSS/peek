# Peek hardening tools

## MiniFASNet → Core ML

Silent anti-spoof model from [Silent-Face-Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) / [yakhyo/face-anti-spoofing](https://github.com/yakhyo/face-anti-spoofing).

```bash
# One-time: clone repo + download weights (see convert script defaults)
python3 -m venv /tmp/peek-coreml-venv
/tmp/peek-coreml-venv/bin/pip install coremltools torch
/tmp/peek-coreml-venv/bin/python tools/convert_minifasnet_coreml.py \
  --weights /path/to/MiniFASNetV2.pth \
  --out glance/Models/MiniFASNetV2.mlpackage
```

Xcode compiles the `.mlpackage` into `MiniFASNetV2.mlmodelc` in the app bundle. `MiniFASNetPAD` loads it at runtime as a deny cue (`silentAntiSpoof`) and Heavy-mode confirm cue (`silentLive`).
