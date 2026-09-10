<h1 align="center">
  <br>
  <a href="https://github.com/XIVASSS/peek"><img src="glance/Assets.xcassets/appicon.imageset/appicon.png" alt="Peek" width="150"></a>
  <br>
  Peek
  <br>
</h1>

<h3 align="center">Face unlock for your Mac</h3>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-black.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black.svg" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-black.svg" alt="Swift">
</p>

Peek brings the Face ID–like experience of your iPhone to a Mac near you. Unlock your Mac with a look — no typing, no reaching for the Touch ID key. Everything runs on-device using Apple's Vision and Core ML frameworks, so your face data and your Mac password never touch the internet. The UI is built into your MacBook's notch with fluid Dynamic Island–like animations.

Built as a hardened fork of [Glance](https://github.com/jonnyoo/glance) — same polished UI, smoother enrollment, stronger anti-photo core.

---

> [!WARNING]
> ## Read before downloading
> ## Peek is not as secure as Apple's Face ID or Touch ID
>
> MacBooks don't come equipped with the depth sensors that make iPhone Face ID trustworthy and secure. An iPhone builds a 3D map of your face; a MacBook webcam sees a flat 2D image. That means:
>
> - Peek defeats, with reasonable confidence, a printed photo and a photo on a phone screen (heavy liveness detection must be turned on)
> - Peek does not reliably defeat a video of you
> - macOS has no API that lets a third-party app authorize a login, so Peek unlocks by typing your stored password on the lock screen
>
> Peek is a convenience feature with strong anti-photo hardening, not a security upgrade over Touch ID. Only continue if you accept the tradeoff.

## Installation

**Requirements:**
- macOS 15 Sequoia or later
- Apple Silicon or Intel Mac

<a href="https://github.com/XIVASSS/peek/releases/latest/download/Peek.dmg" target="_self"><img width="200" src="docs/download-for-mac.png" alt="Download for Mac" /></a>

Open the `.dmg` file and drag Peek to `/Applications`, then open it.

> **If macOS says Peek is “damaged”:** that’s Gatekeeper blocking an unsigned download (not a bad file). Drag Peek to Applications, then double-click **If Peek won't open** on the disk image — or run:
> ```bash
> xattr -cr /Applications/Peek.app && open /Applications/Peek.app
> ```
> (Apple notarization removes this step; requires a Developer ID.)

## Permissions

| Permission | Why |
|---|---|
| **Camera** | To see your face. Frames are processed in memory and never written to disk. |
| **Accessibility** | To type your password into the lock screen. |
| **Touch ID** | Gates the key that encrypts your face data and password. |

## How it works

1. Launch the app and enroll your face — look at the camera, then **slowly turn your head**. The ring fills as Peek captures (no exact-angle hunting). Each frame becomes an ArcFace *embedding* plus a 3D-proxy geometry template; the image is thrown away.
2. Enter your Mac password once, encrypted behind Touch ID.
3. When your Mac locks or wakes from sleep, the animation appears in the notch and starts searching for a face.
4. If it's you — and the liveness checks agree you're a real person — Peek types the password and you're in.

## What's better than Glance

| Area | Peek |
|---|---|
| **Enrollment** | Seamless coverage scan — turn your head naturally |
| **Identity** | ArcFace **+** encrypted multi-pose geometry vault |
| **Anti-photo** | Heavy liveness by default + [MiniFASNet](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) silent anti-spoof |
| **Match** | Stricter defaults; dual ArcFace + geometry gate when vault exists |

## Features

| Feature | Description |
|---|---|
| **Face unlock** | Triggers on wake, on lock, or on pressing space at the lock screen. Pick any combination. |
| **Multiple identities** | Enroll several people, or several versions of yourself — with glasses, a beard, different lighting. Toggle any of them off without deleting. |
| **Liveness checks** | Watches for the motion and reflections that separate a real face from a photo. *Light* or *Heavy* strictness, or off. |
| **Notch UI** | A closed pill that expands into a scan animation with success and failure states. Hover to retry — or turn animations off entirely and Peek stays invisible. |
| **Camera & display** | Choose which camera to use, including different cameras for the built-in display vs. an external monitor. |
| **Auto-locking sessions** | The Touch ID session re-locks itself after an idle period you choose, so an unattended Mac doesn't stay authorized forever. |
| **Trackpad haptics** | Hovering over the notch will trigger haptics |
| **Notchless Mac support** | Macs without a notch will be replaced with a pill-shape, Dynamic Island style design. |
| **Your data, your call** | Edit or delete your enrolment or stored password at any time. The encrypted files are removed immediately. |

---

# Privacy and Security

Peek is designed to keep biometric data and credentials on-device.

### Face data

Peek never stores camera images. During enrollment, each captured face is converted into a **512-dimensional embedding** using an ArcFace-based Core ML model, plus a compact **geometry vault**. The original frame is then discarded.

Embeddings and geometry are stored locally and encrypted with **AES-GCM**.

### Credentials

Your Mac password is stored as encrypted data and is never written to disk in plaintext. The encryption key is a **256-bit AES key stored in the macOS Keychain**, protected by `userPresence` — requiring Touch ID or your device password.

### Local by design

Face recognition, face enrollment, and liveness detection run entirely on-device using Vision and Core ML. Peek does not send face data, camera frames, or credentials to a server.

See [SECURITY_HARDENING.md](SECURITY_HARDENING.md) for the full unlock pipeline and anti-spoof cues.

## Building from source

### Prerequisites

- macOS 15+
- Xcode 26+

### Installation

```bash
git clone https://github.com/XIVASSS/peek.git
cd peek
open glance.xcodeproj
```

Click Run or press `Cmd + R`. (Xcode project folder is still named `glance`; the app product is **Peek**.)

### Package a DMG

```bash
./tools/package_dmg.sh
# → dist/Peek-1.1.0.dmg
```

## Credits

- Forked from **[Glance](https://github.com/jonnyoo/glance)** by Jonathan Zhou (MIT)
- **The Boring Notch** — for the notch window physics
- **InsightFace** — the ArcFace model doing the recognition
- **[Silent-Face-Anti-Spoofing / MiniFASNet](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing)** — on-device photo/screen rejection

## Website

Marketing site (Vercel): see [`website/`](website/).

```bash
cd website
npx vercel --prod
```

## License

MIT — see [LICENSE](LICENSE).
