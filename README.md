# Music Bridge

**Keep your playlists on your iPod.**

A native macOS app for playlist downloads and manual music imports to Rockbox iPods. Paste a public NetEase Cloud Music or Apple Music playlist link, use your local download tools, then choose when to copy the music to your device.

English · [简体中文](README.zh-CN.md)

> Source beta. The app interface is currently in Simplified Chinese. Live playlist downloads and imports to a physical iPod have not yet completed end-to-end validation.

![Music Bridge main window with native macOS window controls and no iPod connected](docs/screenshots/music-bridge-main.jpg)

*Captured from the running app on Apple Silicon with macOS 27.2. This is the idle state with no device connected.*

## Features

- **Playlist input:** recognizes public NetEase Cloud Music and Apple Music playlist links. NetEase tracks are matched to the Apple Music China catalog; uncertain matches are skipped.
- **Local downloads:** calls your separately configured `amdl` and wrapper-lite service, with progress, cancellation and bounded logs.
- **Lossless quality settings:** choose an ALAC ceiling of 192 kHz or 48 kHz and save cover preferences between launches. Actual quality depends on the available source.
- **Manual iPod import:** reads mounted device details and enables import only for a writable, supported device. Downloads never trigger an automatic import.
- **File protection:** checks paths, symbolic links and device identity, uses temporary copy files, and preserves existing files when their sizes differ. Same-path files with matching sizes are skipped.
- **Native desktop interface:** SwiftUI and AppKit, macOS window controls, translucent surfaces, pointer lighting and subtle card movement. Respects Reduce Motion, Reduce Transparency and Increase Contrast.

### Pointer interaction

![Sampled app captures showing the light spot at different pointer positions within the source card](docs/screenshots/pointer-hover.gif)

*Four actual app captures, shown as a slowed sequence of hover states. This is not a real-time frame-rate recording. The full window screenshot above shows the window controls; this close-up focuses on the source card.*

## Build and run

You need macOS and Swift 6 or later with the macOS SDK. The package declares macOS 14 as its minimum; building and launching have been verified on Apple Silicon with macOS 27.2. Older supported systems have not been tested.

From the repository root:

```sh
bash script/build_and_run.sh --verify
```

The script creates and opens `dist/MusicBridgeApp.app`. Building the interface does not require a download service. The app is not Developer ID signed or notarized, and this repository does not provide an installer.

## Configure downloads

Install and configure the external [amdl downloader](https://github.com/zhaarey/apple-music-downloader) and [wrapper-lite service](https://github.com/WorldObservationLog/wrapper/tree/lite) using their upstream instructions. The app expects these paths relative to the project root:

| Path | Purpose |
| --- | --- |
| `amdl` | Downloader executable |
| `config.yaml` | Your downloader configuration |
| `work/wrapper-lite-macos/start-local.sh` | Local wrapper launcher |
| `work/wrapper-lite-macos/` | Wrapper and QEMU runtime files |

The local wrapper endpoint is `http://127.0.0.1:12340`. A valid login, a ready service and an accessible playlist are required. Audio inspection also requires `ffprobe` (available with FFmpeg).

Keep the app in `dist/` relative to the project root so it can find these dependencies. Rebuild after moving the project. Authentication disks, personal configuration, downloaded music, logs and build artifacts are excluded from version control.

## Import to an iPod

1. Connect a mounted, writable Rockbox iPod.
2. Download music using your configured local tools.
3. Select **开始导入** (Start import) to scan the download folders and copy files into the device's `Music/` directory.

The app cannot import while the device is disconnected, read-only or has an unknown write state. It does not overwrite existing files whose sizes differ. Matching file sizes are a skip rule, not a content-identity check. A successful `ffprobe` inspection is not a guarantee of playback on every Rockbox device.

## Checks and current limits

```sh
bash script/check.sh
```

The standalone Swift checks cover link validation, cancellation, download arguments, quality and cover preferences, import guards, path and symbolic-link containment, stale callbacks, process output and bounded pointer input. They use temporary files and injected service responses; they do not sign in, download music or write to a physical device.

The full download and physical-device import workflows still need end-to-end validation. External services may change, and source availability and catalog matching vary by region and release.

## Privacy and license

NetEase playlist links are sent to the third-party GoMusic service. Apple Music matching accesses Apple's public website and catalog endpoints. Login credentials and subscription access are managed through your external tools.

Only process music you have permission to access. Source is licensed under [MIT](LICENSE). Dependency, asset and trademark information is listed in [Third-party notices](THIRD_PARTY_NOTICES.md).
