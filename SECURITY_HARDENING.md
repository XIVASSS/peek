# Security hardening notes

## Architecture

```
Camera frame
    │
    ├─► FaceDetector + FaceAligner + ArcFace ──► identity score
    ├─► FaceGeometryTemplate ──────────────────► geometry vault score (gated)
    └─► LivenessFeatureExtractor
            ├─ Glare / device / PassiveAntiSpoof / MiniFASNet  → DENY cues
            └─ flatVs3D / depthPose / blink / MiniFASNet-live → CONFIRM cues

Unlock iff: session OK ∧ lock screen ∧ ArcFace ∧ geometry vault ∧ liveness
```

## Geometry vault (not TrueDepth)

`FaceGeometryDescriptor` stores:

- **shape** — eye-centered, IOD-scaled landmark centroids (L2-normalized)
- **depth** — nose offset/protrusion, mid-face height, jaw width, brow tilt
- **FaceGeometryProfile** — multi-pose templates + `depthYawCorrelation` / slope from enrollment sweep

Persisted inside encrypted `face-identities.enc` (AES-GCM, Touch ID–gated key). No JPEGs.
Vault is required for unlock when ≥4 templates exist (`hasGeometryVault`).

## Anti-photo stack

| Cue | Role | Source |
|---|---|---|
| `glossGlare` | deny | specular blob on crop |
| `deviceDetected` | deny | phone/tablet rectangle |
| `passiveSpoof` | deny | moiré / sharpness uniformity / banding |
| `silentAntiSpoof` | deny | MiniFASNetV2 Core ML ([Silent-Face-Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing)) |
| `flatVs3D` | confirm | homography residual on nose |
| `depthPose` | confirm | noseOffset ↔ tan(yaw) |
| `blink` | confirm | EAR dip/recover |
| `silentLive` | confirm | MiniFASNet P(real) |

Defaults: **Heavy** liveness, match threshold **0.68**, geometry floor **0.72**.

## Next upgrades (optional)

1. **DECA / FLAME** shape coefficients for a denser morphable 3D identity.
2. **Challenge-response** at unlock (“look left”) when MiniFASNet is borderline.
3. **Virtual camera** blocklist (OBS etc.) on macOS.
4. **Developer ID + notarization** for public DMG downloads.

## What this still cannot do

Without IR depth / structured light, a high-quality video replay of the enrolled user remains the main residual risk. Treat this as **strong convenience with anti-photo hardening**, not Apple Face ID.
