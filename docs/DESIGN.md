# Design

Screentime++ should feel like an Apple utility that was given more time: native
controls and navigation, calmer typography, and a small number of details made
with extra care. It measures time and enforces shields; it never lectures.

## Direction

Warm minimal with an information core. The data (time, sites, matches) is the
content; chrome stays out of the way. Rejected directions: dense "dashboard"
grids (too noisy for a wellbeing tool) and expressive colour fields (they
compete with app icons, which already carry identity).

## Tokens

All tokens live in `Sources/ScreentimeApp/Design/Theme.swift`.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `ember` (accent) | `#C8502A` | `#F0794A` | Controls, selection, active shields, the focus ring |
| `canvas` | system window background | system window background | Window panes |
| `inkSecondary` | system secondary label | system secondary label | Captions and metadata |
| Category `social` | `#D9623F` | `#EE7E5E` | Usage series |
| Category `entertainment` | `#9A5A86` | `#C083AE` | Usage series |
| Category `productivity` | `#4F8C69` | `#79B892` | Usage series |
| Category `communication` | `#3A8592` | `#66B2BE` | Usage series |
| Category `reading` | `#B88A2E` | `#DDB25A` | Usage series |
| Category `games` | `#C4566F` | `#E27E95` | Usage series |
| Category `shopping` | `#C97C34` | `#E9A05E` | Usage series |
| Category `other` | `#8F887F` | `#A9A299` | Usage series |

Red is reserved for failures and destructive actions. Warnings and successes
always pair colour with text and an SF Symbol.

### Type

- Display: New York (`.system(design: .serif)`), 34 to 56 pt, for screen titles
  and the single headline number on a screen.
- Heading: SF Pro semibold 15 to 20 pt.
- Body: SF Pro 13 pt (macOS body).
- Caption: SF Pro 11 to 12 pt, secondary.
- All durations and clock times use `.monospacedDigit()`.

### Spacing and shape

8 pt grid: 4, 8, 16, 24, 32, 48. Continuous corner radii of 8 (thumbnails,
chips), 12 (grouped panels) and 20 (shield card). Prefer alignment and spacing
over nested cards.

## Signature details

One per surface, built at 120 percent:

- Today: the oversized serif total and the **day ribbon**, a 24-hour band where
  each minute of use is drawn in its category colour, with a live "now" tick.
- Shield: a glass card over exactly the offending window. "Allow 1 minute"
  requires a press-and-hold whose ring fills over two seconds, so overrides are
  deliberate rather than reflexive.
- Focus: a single ember arc that drains as the session runs.
- Menu bar: the same ribbon in miniature, so the status item reads at a glance.

## Motion

Short, explanatory transitions only (shield appear, ring fill, arc drain).
Respect Reduce Motion. No looping decoration. The shield must never flicker:
it is shown on a positive match and hidden only on a positive non-match.

## Copy

Second person, short, factual. "Blocked by Deep Work until 17:00", not
"Oops! Time to focus!". No emoji in UI.

## Review

Every surface is reviewed rendered in light and dark at 900 x 600 and
1,280 x 820 against the five dimensions (philosophy, hierarchy, craft,
functionality, originality). Scores are judgements; defects are recorded and
fixed, not averaged away.
