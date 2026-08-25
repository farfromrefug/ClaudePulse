# Pulse for Claude Code

A macOS menu bar app that brings **Dynamic Island-inspired** real-time monitoring to your Claude Code sessions.

![Demo](docs/demo.gif)

## Features

- **Dynamic Island Style** — A compact capsule UI floats above your screen, expanding on hover to show full session details
- **Real-time Session Tracking** — Monitor multiple Claude Code sessions simultaneously with working, waiting, or idle status
- **Elegant Animations** — Smooth expand/collapse, pulse effects on state changes, and frosted glass materials
- **Fully Local** — All data stays on localhost via Claude Code hooks. Nothing leaves your machine
- **Menu Bar Integration** — Quick controls from the system menu bar: show/hide, pin expanded view, adjust position
- **Zero Configuration** — Automatically sets up Claude Code hooks on first launch

## Session States

| State | Description |
|-------|-------------|
| **Working** | Claude is processing |
| **Waiting** | Waiting for user input or approval |
| **Idle** | Session is idle |
| **Stale** | No activity for over 10 minutes |

## Install

Download the latest DMG from [Releases](https://github.com/tzangms/ClaudePulse/releases/latest).

### Build from Source

```bash
git clone https://github.com/tzangms/ClaudePulse.git
cd ClaudePulse
swift build -c release
```

### Develop in Xcode

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not committed — edit `project.yml`, never the project file.

```bash
brew install xcodegen
./scripts/gen-xcode.sh
open ClaudePulse.xcodeproj
```

`project.yml` points at the `Sources` directory rather than listing files, so
**adding a file means re-running `./scripts/gen-xcode.sh`** — otherwise Xcode
compiles a project that has never heard of it and fails with
`Cannot find type ... in scope`, while `swift build` succeeds.

Run tests from either toolchain:

```bash
swift test
```

## How It Works

Pulse installs `type: "http"` hooks into `~/.claude/settings.json` pointing at
`http://127.0.0.1:19280/hook`. Claude Code POSTs each event directly to the app —
no `curl`, no polling — and reads the HTTP response as the hook's output.

That response channel is what makes in-panel permissions possible: when
**Answer Permissions in Pulse** is on, the app holds the `PermissionRequest`
hook open while it shows Allow / Allow all / Deny, then replies with the
decision. **Allow all** returns the same `permission_suggestions` Claude Code
would have offered in its own prompt, so the rule is persisted identically. If
nobody answers within the configured wait, Pulse replies with no decision and
Claude Code prompts in the terminal as usual.

Clicking a session uses whatever Pulse knows about it. When the hook headers
identify a terminal, that exact tab or pane is focused. Otherwise Pulse looks
for the session in Claude for Desktop and focuses it there, falling back to
simply bringing that app forward. Option-click always aims at Claude, and
**Settings → Reveal In** pins one target for every click.

Focusing a desktop session takes two steps, because the hook only ever reports
the Claude Code session id and the desktop app files its sessions under ids of
their own. Pulse reads the records in
`~/Library/Application Support/Claude/claude-code-sessions`, picks the live one
claiming that CLI session, and navigates to it with
`claude://claude.ai/epitaxy/<desktop-id>`.

Pulse never imports a session. `claude://resume?session=<id>` looks like the
link to use and is not: handed a session the app has no record of *under that
name*, it copies the transcript into a brand new session instead of focusing
anything — which is almost always, since the ids rarely match.

Every other event is answered immediately, with a 3 second hook timeout, so a
stopped or wedged Pulse can never stall a session.

Existing settings are backed up to `~/.claude/settings.json.ccpulse-backup`
before any change, and hooks from other tools are left untouched.

## Tech Stack

- Swift 5.10+ / SwiftUI / AppKit
- POSIX Sockets
- macOS 14+
- Swift Package Manager

## License

MIT

## Support

<a href="https://www.buymeacoffee.com/tzangms" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="48"></a>

## Author

Built by [@tzangms](https://github.com/tzangms)
