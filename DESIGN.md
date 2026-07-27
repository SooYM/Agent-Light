# Token Signal Design System

## Thesis

Compact macOS instrument answering one question at a glance: “Is my agent
working?” Reading order is phase, tokens, agent count, then back to work.

## Visual System

- Instrument face: `#0E0F10`; recessed signal rail: black at 18% opacity.
- Primary text: white; secondary: white at 58%; tertiary: white at 45%.
- Stopped: `#FF404A`; preparing: `#FF9129`; running: `#33DB75`.
- State color is reserved for phase, with inactive lamps at 10% opacity.
- System fonts only: 42 pt monospaced token total, 11 pt rounded status and
  metadata, 10 pt monospaced token label.

## Composition

Fixed `370 × 196 pt` floating panel. A `104 pt` left rail holds three stacked
`40 pt` lamps in red, orange, green order. A one-point divider separates it
from telemetry. A three-point state rule runs across the top. The right field
holds text status, token total, coverage label, provider name, and agent count.

## States

Running takes precedence over preparing, then stopped. Phase is communicated
by lamp position, color, and text. Missing tokens display `—`; partial provider
coverage displays `TOKENS / REPORTED`. Numeric changes animate in place.

## Platform Behavior

Native nonactivating `NSPanel`; floats above standard windows, joins all
Spaces, remains available beside full-screen apps, remembers position, and is
shown or hidden from a menu-bar item. Its colored lamp mirrors current phase;
tooltip and accessibility label repeat the status in text.

## Accessibility

Combined panel label announces phase and tokens. Every lamp exposes its name
and on/off value. Provider and agent metadata remain readable text rather than
color-only signals.
