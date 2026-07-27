# Agent Light

Agent Light is a small, always-on-top macOS traffic-light monitor for local AI
coding agents. It shows whether an agent is preparing, running, or stopped,
plus locally reported token usage and active-agent count.

Supported providers:

- OpenAI Codex
- Anthropic Claude Code
- Google Antigravity

## Status lights

| Light | Status | Meaning |
| --- | --- | --- |
| Green | Running | At least one agent is actively working |
| Orange | Preparing | A new agent turn is starting |
| Red | Stopped | No detected agent is working |

Running takes priority over preparing when several agents are active.

## Requirements

- macOS 14 Sonoma or newer
- Apple silicon Mac
- One or more supported agent tools installed locally
- Xcode 16+ or Swift 6 only when building from source
- macOS built-ins `/usr/bin/sqlite3` and `/usr/bin/pgrep`

## Run the included app

1. Download or clone this repository:

   ```sh
   git clone https://github.com/SooYM/Agent-Light.git
   cd Agent-Light
   ```

2. Unzip the bundled build:

   ```sh
   ditto -x -k "outputs/Token Signal.zip" outputs
   ```

3. Launch it:

   ```sh
   open "outputs/Token Signal.app"
   ```

Token Signal opens as a floating panel and adds a color-coded indicator to the
menu bar: red when stopped, orange while preparing, and green while running.
Its traffic-light app icon also remains in the Dock; clicking it reopens a
hidden panel.
Closing the panel leaves the menu-bar app running. Open its menu and choose
**Show Token Signal**, **Hide Token Signal**, or **Quit**. Enable **Light Only
Mode** to collapse the panel to the three status lights and hide all token and
provider details. The choice persists between launches.

Large token totals shrink to fit the telemetry field, so the complete number
remains visible instead of ending in an ellipsis.

If macOS blocks the first launch, Control-click `Token Signal.app`, choose
**Open**, then confirm **Open**.

## Run from source

For development:

```sh
swift run TokenSignal
```

Build and package a signed local app:

```sh
zsh scripts/build-app.sh
open "outputs/Token Signal.app"
```

The build script creates an ad-hoc signed app at
`outputs/Token Signal.app`; it does not regenerate the ZIP. No Apple Developer
account is required for local use. The app is not Developer ID signed or
notarized, so Gatekeeper may show a first-launch warning.

## Test

```sh
swift test
```

Tests cover status priority, active token aggregation, stopped-state totals,
local data parsing, and partial provider reporting.

## Token accounting

Agent Light reads local provider data; it does not call provider APIs.

| Provider | Activity status | Token usage |
| --- | --- | --- |
| Codex | Local lifecycle database | Cumulative local thread total |
| Claude Code | Local process and session JSONL | Cumulative local session total |
| Antigravity | Local trajectory and completion state | Not exposed exactly |

When every active provider exposes a count, the panel shows `TOKENS`. When
only some do, it shows `TOKENS / REPORTED`. Antigravity running alone displays
`—` instead of inventing a token estimate.

Token values are local cumulative counts, not billing totals or remaining
context-window capacity.

## Privacy

- No network requests
- No API keys read
- No telemetry
- Provider stores opened read-only
- All calculation stays on the Mac
- Light Only Mode removes the token total from both the panel and its
  accessibility summary

Local data sources currently include:

- `~/.codex/logs_2.sqlite`
- `~/.codex/state_5.sqlite`
- `~/.claude/projects/**/*.jsonl`
- Antigravity state under `~/Library/Application Support`

## Project structure

```text
Sources/TokenSignal/       macOS panel, menu-bar item, provider readers
Sources/TokenSignalCore/   provider-neutral status and token aggregation
Tests/                     Swift Testing checks
Resources/Info.plist       app bundle metadata
Resources/AppIcon.svg      editable traffic-light app icon source
Resources/TokenSignal.icns packaged macOS app icon
scripts/build-app.sh       release packaging script
outputs/Token Signal.zip   ready-to-run local build
```

## Known limitations

- Antigravity does not expose an exact local token total.
- Codex scans the last 12 hours, caps results at 200 threads, and closes stale
  activity after 30 minutes.
- Claude Code follows the newest local project session and an exact `claude`
  process name. Its total includes input, cache-creation, cache-read, and output
  tokens.
- Antigravity activity detection is heuristic and begins after local trajectory
  state changes while Agent Light is running.
- Local provider storage formats may change in future provider releases.
- Current binary targets Apple silicon and macOS 14+.
- No launch-at-login, automatic update, or provider-specific error screen yet.
