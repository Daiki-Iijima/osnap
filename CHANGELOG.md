# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `.claude/skills/osnap/SKILL.md` — Claude Code skill so the agent will
  automatically reach for `osnap` instead of full-screen `screencapture`
  when a task involves a targeted macOS capture.
- README sections (English and Japanese) describing how to install the
  skill per-user or per-project.

## [0.1.0] — 2026-05-28

### Added

- `osnap list` — enumerate on-screen windows with ID, owner, layer, bounds.
- `osnap region` — capture an explicit screen rectangle.
- `osnap window` — capture a single window by `CGWindowID`.
- `osnap app` — capture every visible window of an app.
- `osnap menubar-popup` — open an app's menu-bar extra via Accessibility and
  capture only the resulting popup.
- `osnap popup-wait` — wait for a new popup window and capture it; works
  without Accessibility permission.
- MIT license, public README.

### Known limitations

- AppKit `AXShowMenu` may fail on SwiftUI `MenuBarExtra` items; document
  AppleScript + `popup-wait` workaround.
- No automated tests yet.
- Tested only on macOS 26 (Tahoe).
