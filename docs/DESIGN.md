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
| `accent` | `#2E7D57` | `#3FAE77` | Controls, selection, positive states (on track, turned back), the focus ring |
| `caution` | `#B26B12` | `#E3A040` | Over goal, overrides, missing permission, paused rules |
| `canvas` | system window background | system window background | Window panes |
| `inkSecondary` | system secondary label | system secondary label | Captions and metadata |
| Category `social` | `#D9623F` | `#EE7E5E` | Usage series |
| Category `entertainment` | `#9A5A86` | `#C083AE` | Usage series |
| Category `productivity` | `#4A72A8` | `#7FA4D6` | Usage series |
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
- Shield: a calm, opaque card over exactly the offending window or page. "Allow 1 minute"
  requires a press-and-hold whose ring fills over two seconds, so overrides are
  deliberate rather than reflexive.
- Focus: a single green arc that drains as the session runs.
- Menu bar: a 16 pt goal ring in the status item (amber once over goal), and
  the day ribbon in miniature inside the panel.

## Motion

Short, explanatory transitions only (shield appear, ring fill, arc drain).
Respect Reduce Motion. No looping decoration. The shield must never flicker:
it is shown on a positive match and hidden only on a positive non-match.

## Previews and accessibility

Before any activity is recorded, Today explains the report, shows the app being
watched, and opens the Library. The rule editor and Library rule details share
a non-interactive, scaled rendering of the real shield; previews never start
enforcement or a countdown. Track rules explain why no shield is shown.

The rule editor starts with an editable sentence: choose its highlighted
subject, schedule, response or daily allowance. Exceptions stay in the sentence;
precise controls live in Details, expanded initially for multiple time windows.
Rules rows reuse the same wording and show today's progress against each limit.
Deleting or toggling a rule supports the window's Undo/Redo commands; deletion
does not ask for confirmation. Rules → Lock offers the same no-early-unlock
confirmation as Settings.

Setup offers a live three-second pause before Start. Its session and turn-back
buttons finish the demo without opening, closing or granting access to anything.
Every shield has a pointer-operated “Why am I seeing this?” disclosure showing
the matched rule, app/site/page/category or counted phrases, the active schedule
or Focus window, and daily limits. Edit Rule opens that existing rule in Rules.
The evidence stays inside the shield, with scrolling for smaller windows.

Custom controls expose their labels and selection state to VoiceOver. Chips
and hold controls use minimum rather than fixed text heights. Theme tracks,
hairlines and soft fills strengthen with Increased Contrast; shared controls
also resolve SwiftUI's contrast environment for previews. Reduce Motion keeps
countdowns factual without animated transitions.

Inspector page text keeps its selection and scroll position between clock
ticks. It updates only for a new source or capture, inside a stable scroll area.


## Copy

Second person, short, factual. "Blocked by Deep Work until 17:00", not
"Oops! Time to focus!". No emoji in UI.

## Review

Every surface is reviewed rendered in light and dark at 900 x 600 and
1,280 x 820 against the five dimensions (philosophy, hierarchy, craft,
functionality, originality). Scores are judgements; defects are recorded and
fixed, not averaged away.

Debug builds include a gallery for this. Run an isolated copy with its own data
folder so real history and rules are untouched:

```sh
SCREENTIME_DATA_DIR=/tmp/screentime-qa \
  "build/DerivedData/Build/Products/Debug/Screentime++.app/Contents/MacOS/Screentime++" \
  --qa-gallery
```

Every sheet, settings pane, the menu bar panel, each shield variant and the
toast open in titled windows ("QA ..."), so each can be captured by window ID
(`screencapture -l`). Add `-NSRequiresAquaSystemAppearance YES` for light mode.

The gallery includes Today First Day, Editor Shield Preview, Library Rule
Preview and Increased Contrast windows.
