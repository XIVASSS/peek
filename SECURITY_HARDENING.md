# Security hardening notes

## Architecture

```
Camera frame
    │
    ├─► FaceDetector + FaceAligner + ArcFace ──► identity score
    ├─► FaceGeometryTemplate ──────────────────► geometry vault score
    └─► LivenessFeatureExtractor
            ├─ Glare / device bezel / PassiveAntiSpoof  → DENY cues
            └─ flatVs3D / depthPose / blink             → CONFIRM cues

Unlock iff: session OK ∧ lock screen ∧ ArcFace ∧ geometry ∧ liveness
```

## Geometry vault (not TrueDepth)

`FaceGeometryDescriptor` stores:

- **shape** — eye-centered, IOD-scaled landmark centroids (L2-normalized)
- **depth** — nose offset/protrusion, mid-face height, jaw width, brow tilt
- **FaceGeometryProfile** — all pose templates + `depthYawCorrelation` / slope from enrollment sweep

Persisted inside encrypted `face-identities.enc` (AES-GCM, Touch ID–gated key). No JPEGs.

## Anti-photo stack

| Cue | Role | Source |
|---|---|---|
| `glossGlare` | deny | specular blob on crop |
| `deviceDetected` | deny | phone/tablet rectangle |
| `passiveSpoof` | deny | moiré / sharpness uniformity / banding |
| `flatVs3D` | confirm | homography residual on nose |
| `depthPose` | confirm | noseOffset ↔ tan(yaw) |
| `blink` | confirm | EAR dip/recover |

Defaults: **Heavy** liveness, match threshold **0.68**, geometry floor **0.78**.

## Next upgrades (optional)

1. **MiniFASNet** ONNX → Core ML as an extra deny cue (see `tools/convert_minifasnet_coreml.py`).
2. **DECA / FLAME** shape coefficients for a true morphable 3D identity (heavier; Python sidecar or Core ML export).
3. **Challenge-response** at unlock (“look left”) to force parallax every time.
4. **Virtual camera** blocklist (OBS etc.) on macOS.

## What this still cannot do

Without IR depth / structured light, a high-quality video replay of the enrolled user remains the main residual risk. Treat this as **strong convenience with anti-photo hardening**, not a bank-grade authenticator.
