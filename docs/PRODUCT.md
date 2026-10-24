# Product

## Thesis

On a Mac, distraction rarely lives in a whole app. It lives *inside* a site:
YouTube Shorts but not the conference talk, the Reddit front page but not the
thread you searched for, the X timeline but not the DM. Existing Mac blockers
work on domains, so they are either too blunt to keep on or too weak to help.

Screentime++ reads what is actually on screen (address, path, title and page
text through Accessibility) and answers with the lightest intervention that
works: a pause, a short session, or a wall. Everything is decided and kept on
this Mac.

## Lessons taken from ScreenZen

ScreenZen (iOS) succeeds because it adds *friction and intention* rather than
only walls. Its strategies, and how they map here:

| ScreenZen | Screentime++ |
| --- | --- |
| Delay before opening, growing with each open | **Pause** response: breathing wait; `+N` seconds per open today |
| "Is this important?" prompt | Optional intention prompt on the pause card; recorded in History |
| Short sessions that interrupt scrolling | After a pause you choose 2, 5 or 15 minutes; when it ends the pause returns |
| App goal, optional block at limit | Per-rule daily minutes and/or opens; exceeding them escalates to Block |
| Per weekday and time configuration | Rule schedules (weekly windows, overnight aware) |
| Strict block by time, opens or usage | Block response, limits, and locked Focus sessions |
| Settings lock | **Lock rules until** a time: rules can be added or tightened, never weakened |
| Screen time for distracting apps only | Today leads with *distracting time* (time matched by any rule) against a daily goal |
| Streaks | Days under goal without overrides |
| Minimal mode (no Reels/Shorts/feeds) | Built-in **surface** rules by URL path, plus deep content phrases |

What the Mac makes possible beyond ScreenZen: page-level and phrase-level
rules in every major browser, a live inspector that shows exactly what the
engine sees, and tracking at the level of *surfaces* ("YouTube: Shorts 41m,
Watch 22m").

## Vocabulary

- **Activity**: recorded foreground time per app, site and surface.
- **Rule**: *what* (apps, sites, URL patterns, categories, phrases), *except*,
  *when* (always, weekly windows, or only during Focus), *response*, *limits*.
- **Response**: Track (count only), Pause, or Block.
- **Shield**: the card drawn over the offending window.
- **Focus**: a timed session that escalates chosen rules to Block; can be locked.

## Decisions

1. **Accessibility, not a network extension.** A content filter extension sees
   bytes, not rendered pages, needs a system extension approval flow, and is
   painful to remove. AX gives the exact page, title and text in the focused
   window with one permission and no kernel or network components.
2. **Shield over the window, non-activating.** The panel tracks the window
   frame and never takes focus, so the browser stays frontmost and our own app
   switching cannot cause a show/hide loop. It appears on a positive match and
   hides only on a positive non-match; transient AX timeouts keep the current
   state.
3. **Park the tab.** For scriptable browsers (Safari, Chrome family, Arc) the
   blocked tab is replaced with a blank page so media stops and the page cannot
   be used behind the shield. Continuing restores the original address. Other
   browsers fall back to the shield plus Go Back / Close Tab.
4. **Content stays in memory.** Page text is matched and discarded. The
   database stores time, bundle IDs, domains and surfaces; never titles, URLs
   beyond the host, or page text.
5. **Opens are counted when access begins** (entering an allowed match after a
   minute away, or finishing a pause), not when a shield is shown.
6. **Shielded time is not usage.** Time spent looking at a pause card does not
   count toward limits.
7. **Overrides are deliberate.** A one-minute override needs a two-second
   press-and-hold, is logged, and breaks the streak. Locked Focus disables it.

## Non-goals (for now)

- Cross-device sync.
- Blocking at the network layer for apps without a window (background
  downloads, CLI tools).
- Parental control. This is a tool you point at yourself; it raises the cost
  of a reflex, it is not tamper-proof against an administrator.
