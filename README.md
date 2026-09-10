#   
Peek   
 Peek  

### Face unlock for your Mac — smoother, stronger

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black.svg)](#installation)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](#building-from-source)

Peek brings a Face ID–like unlock to your Mac. Unlock with a look — no typing, no reaching for Touch ID. Everything runs on-device with Apple Vision and Core ML. Your face data and Mac password never leave your machine.

Built as a hardened fork of [Glance](https://github.com/jonnyoo/glance) — same polished notch UI, better enrollment and anti-photo core.

---

> [!WARNING]
> ## Read before downloading
>
> ## Peek is not as secure as Apple's Face ID or Touch ID
>
> MacBooks don't have TrueDepth. Peek uses the webcam (2D) plus geometry vaults and liveness checks.
>
> - Defeats printed photos and phone-screen photos with high confidence (keep **Heavy** liveness on)
> - Does **not** reliably defeat a video of you
> - Unlocks by typing your stored password (macOS has no third-party login API)
>
> Convenience with strong anti-photo hardening — not a bank-grade authenticator.

## Installation

**Requirements:** macOS 15 Sequoia or later · Apple Silicon or Intel

**[Download for Mac](https://github.com/XIVASSS/peek/releases/latest)**

Open the `.dmg`, drag **Peek** to `/Applications`, then open it.

## Permissions

| Permission | Why |
| --- | --- |
| **Camera** | To see your face. Frames stay in memory and are never written to disk. |
| **Accessibility** | To type your password on the lock screen. |
| **Touch ID** | Gates the key that encrypts your face data and password. |

## How it works

1. Launch Peek and enroll — look at the camera, then **slowly turn your head**. The ring fills as it captures (no exact-angle hunting).
2. Each frame becomes an ArcFace embedding **plus** a 3D-proxy geometry template. Images are discarded.
3. Enter your Mac password once; it’s encrypted behind Touch ID.
4. On lock/wake, the notch UI scans. If it’s you **and** liveness + geometry agree, Peek types the password.

## What’s better than stock Glance

| Area | Peek |
| --- | --- |
| **Enrollment** | Seamless coverage scan — turn your head naturally |
| **Identity** | ArcFace **+** encrypted multi-pose geometry vault |
| **Anti-photo** | Heavy liveness by default + texture/moire/screen deny cue |
| **Match** | Stricter defaults; dual gate when vault exists |

## Features

Same great UX as Glance: notch animations, multiple identities, camera/display pickers, auto-locking sessions, haptics, notchless Mac support.

## Privacy

- No face images stored — embeddings + geometry floats only  
- AES-GCM encryption, Touch ID–gated Keychain key  
- Fully on-device — no server  

## Building from source

```bash
git clone https://github.com/XIVASSS/peek.git
cd peek
open glance.xcodeproj   # Xcode project folder name; app product is Peek
```

Requirements: macOS 15+, Xcode 26+

### Package a DMG

```bash
./tools/package_dmg.sh
# → dist/Peek-1.1.0.dmg
```

## Credits

- Forked from **[Glance](https://github.com/jonnyoo/glance)** by Jonathan Zhou (MIT)  
- **The Boring Notch** — notch window physics  
- **InsightFace** — ArcFace recognition model  

## License

MIT — see [LICENSE](LICENSE). Upstream copyright Jonathan Zhou; Peek modifications © XIVASSS contributors.
