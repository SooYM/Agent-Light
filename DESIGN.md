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
  metadata, 10 pt monospaced token label. Long totals scale down on one line;
  they are never truncated.

## Composition

Default `370 × 196 pt` floating panel. A `104 pt` left rail holds three stacked
`40 pt` lamps in red, orange, green order. A one-point divider separates it
from telemetry. A three-point state rule runs across the top. The right field
holds text status, token total, coverage label, provider name, and agent count.
Light Only Mode collapses the panel to `104 × 196 pt` and removes the divider,
telemetry field, and window control entirely.

## States

Running takes precedence over preparing, then stopped. Phase is communicated
by lamp position, color, and text. Missing tokens display `—`; partial provider
coverage displays `TOKENS / REPORTED`. Numeric changes animate in place.

## Platform Behavior

Native nonactivating `NSPanel`; floats above standard windows, joins all
Spaces, remains available beside full-screen apps, remembers position, and is
shown or hidden from a menu-bar item. Its colored lamp mirrors current phase;
tooltip and accessibility label repeat the status in text. Light Only Mode is
available from the same menu and persists between launches.

## Accessibility

Combined panel label announces phase and tokens in the full layout, and phase
only in Light Only Mode. Every lamp exposes its name and on/off value. Provider
and agent metadata remain readable text rather than color-only signals.
