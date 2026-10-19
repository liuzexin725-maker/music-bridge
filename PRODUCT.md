# Music Bridge

Native macOS software for pasting a public NetEase or Apple Music playlist, downloading locally, and explicitly importing downloaded music to a writable Rockbox iPod.

## Platform
macOS 14+, SwiftUI hosted in an AppKit window, SwiftPM executable packaged as an application.

## Confirmed requirements
- The user-supplied screenshot is the sole visual authority. Preserve its Chinese copy, two-column composition, colors, typography, card sizes, input and button geometry.
- Always run against real local services and real volume detection. No demonstration mode, fixed device name, fictitious writable state, or demonstration badge. Device access can be writable, read-only, or unconfirmed; allow import only for verified writable devices.
- Offer ALAC lossless with maximum sample rates of 192 kHz (default highest) and 48 kHz. Persist the selection and pass the corresponding --alac-max argument to the downloader. Actual source quality may be lower.
- Keep downloads and iPod import separate. Never import automatically.
- Preserve the Muse backup. Use only a project-local copy of the 67108864-byte disk.
- No commits, pushes, deployment, or external account changes are requested.
- The 2026-10-16 revision adds system translucency, bounded pointer-responsive panel motion and coherent interruptible state transitions. Respect Reduce Motion, Reduce Transparency and Increased Contrast. Keep directory scans off the UI thread and preserve real device state.

## Runtime
The existing amdl executable and wrapper-lite QEMU assets are copied locally from the surviving iPod workspace. Restored disk presence does not prove that the saved Apple login is still valid.
