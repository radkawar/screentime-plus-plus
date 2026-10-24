# Screentime++

Screen time for the Mac that controls **apps and websites equally**, and then
goes one level deeper: what is *inside* them. YouTube without Shorts. Slack
without `#random`. Every game, blocked on weekdays. Any page that talks about
betting. A breath before chat apps, a little longer each time.

Screentime++ reads the app, window title, address and visible text in front of
you through macOS Accessibility, decides on this Mac, and answers with the
lightest intervention that works:

- **Track**: count time and opens.
- **Pause**: a breathing wait (longer with every open today), an optional
  "what are you here for?", then a 2, 5 or 15 minute session. When it ends, the
  pause comes back.
- **Block**: a calm shield over the app (every window) or the page. Browser tabs
  are blanked so audio and video stop. Overrides take a deliberate two-second
  press and hold, and break your streak.

Rules combine apps, websites, page patterns (`youtube.com/shorts/*`,
`reddit.com/`), categories (every installed app by the category it declares),
and phrases (optionally only inside one app), with exceptions, weekly
schedules, and daily time or open limits. Focus sessions escalate chosen rules
to Block, and can be locked. Rules themselves can be locked until a time.

Everything stays on this Mac. History keeps time, app identifiers, website
hosts and page surfaces (such as "Shorts"), never full addresses, titles or
page text.

## Install

Download `ScreentimePlusPlus-latest-macos-universal.dmg` from
[Releases](https://github.com/radkawar/screentime-plus-plus/releases/latest),
open it and drag Screentime++ to Applications. Requires macOS 15 or later.

On first launch, turn on Screentime++ in System Settings > Privacy & Security >
Accessibility. The first time a tab is blanked, macOS asks once per browser to
allow Automation.

## Develop

```sh
swift test                 # core engine tests
Scripts/xcodegen.sh generate
Scripts/build.sh           # Debug build, ad-hoc signed
```

`Sources/ScreentimeCore` holds the engine (rules, matching, policy, Accessibility
reader, usage store); `Sources/ScreentimeApp` the SwiftUI app, menu bar extra
and shield. Design rules live in [docs/DESIGN.md](docs/DESIGN.md), product
decisions in [docs/PRODUCT.md](docs/PRODUCT.md), and shipping in
[docs/RELEASING.md](docs/RELEASING.md).

## License

MIT
