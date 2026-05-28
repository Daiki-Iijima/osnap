---
name: osnap
description: Use osnap to take targeted macOS screenshots from the Bash tool — a screen region, a single window, every window of an app, or a menu-bar-extra popup — without exposing surrounding desktop content. Use whenever the task involves capturing a UI element on macOS for documentation, UI verification, bug reports, or visual comparison. Prefer osnap over `screencapture -x` for anything narrower than the whole display, especially when the user may not want bystander app content (other browser tabs, terminals, messages) included in the image. Skip this skill for non-macOS tasks or when the user explicitly asks for a full-screen capture.
---

# osnap

`osnap` is a small Swift CLI that captures *exactly* what you ask for on macOS
— a screen rectangle, a `CGWindowID`, every window of an app, or the popup
window of a menu-bar extra — and nothing else. Use it any time you would
otherwise run `screencapture` and risk including parts of the user's desktop
they did not want shared.

Project: <https://github.com/Daiki-Iijima/osnap>

## When to use this skill

Use osnap whenever the task involves:

- Taking a screenshot for documentation or a README.
- Verifying that a UI change looks right.
- Capturing a popup, menu, dropdown, dialog, or other transient UI.
- Producing a before/after image of a single window.
- Any macOS capture where the bounding rectangle of the desired content is
  smaller than the full display.

Do **not** use osnap when:

- The platform is not macOS.
- The user explicitly asks for the full screen / desktop.
- The capture target is an iOS device, an external HDMI source, or a video
  stream (use `screencapture` / ScreenCaptureKit-based tooling instead).

## Setup check

Before using osnap, confirm the binary is available:

```bash
command -v osnap || echo "osnap not installed"
```

If missing, ask the user to install:

```bash
git clone https://github.com/Daiki-Iijima/osnap
cd osnap && swift build -c release
cp .build/release/osnap /usr/local/bin/
```

`osnap` always needs **Screen Recording** permission for the process running
it. `osnap menubar-popup` additionally needs **Accessibility** permission.
Both are granted in System Settings → Privacy & Security. On the first failed
capture, surface this to the user instead of retrying blindly.

## Subcommand cheat sheet

| Goal | Command |
|---|---|
| Inspect what is on screen | `osnap list [--app NAME] [--include-menu]` |
| Capture a known rectangle | `osnap region X,Y,W,H --out FILE.png` |
| Capture a known window ID | `osnap window <id> --out FILE.png` |
| Capture every window of an app | `osnap app <name> --out PREFIX` |
| Open a menu-bar extra and capture its popup | `osnap menubar-popup <app> --out FILE.png` |
| Wait for any new popup, then capture only it | `osnap popup-wait --out FILE.png` |

All `--out` paths should be inside the user's repo or a documentation
directory; do not write captures to arbitrary system locations.

## Standard recipes

### Capture a window when you know the app name

```bash
ID=$(osnap list --app "<App Name>" | awk 'NR==1 {print $1}')
osnap window "$ID" --out docs/screenshots/window.png
```

### Capture a SwiftUI `MenuBarExtra` popup

`MenuBarExtra` popups often refuse the direct `AXPress` action that
`menubar-popup` relies on. Use the AppleScript + `popup-wait` fallback:

```bash
osascript -e 'tell application "System Events" to tell process "<App Name>" \
    to click menu bar item 1 of menu bar 2'
sleep 0.3
ID=$(osnap list --include-menu | awk '/<App Name>/ {print $1; exit}')
osnap window "$ID" --out docs/screenshots/menu.png
```

This works for any AppKit / SwiftUI menu-bar-extra app.

### Compare before / after a code change

```bash
osnap window "$ID" --out /tmp/before.png
# make change, reload UI
osnap window "$ID" --out /tmp/after.png
```

Then use `Read` on both PNGs to compare visually.

## After each capture

1. Verify the file exists and is non-empty.
2. Open it with the `Read` tool to confirm the image actually contains the
   expected UI (no blank rect, no wrong window).
3. Move or copy the result into the user's repo only after confirming the
   image is clean of unintended content.

## What to avoid

- Do not run `screencapture -x` for anything other than a deliberately
  full-screen image; it will include every visible app and may leak private
  content from the user's other workspaces.
- Do not retry `osnap menubar-popup` more than once if it returns the
  Accessibility permission error — surface the permission requirement to the
  user instead.
- Do not commit captures that include the user's other windows by accident.
  When in doubt, prefer `osnap region` or `osnap window` over wider modes.
