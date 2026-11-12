# Changelog

Every Marmot release, newest first. Downloads are on [GitHub Releases](https://github.com/Kasakir-AI/Marmot/releases).

## Unreleased

For people who build Marmot themselves; nothing changes in the app.
- `make` now builds `build.noindex/Marmot.app` instead of `Marmot.app` in the project folder, and tells Launch Services to forget it. Spotlight skips `.noindex` folders, so only the installed Marmot shows up in Spotlight, Launchpad and search. A leftover `Marmot.app` from older builds is removed on the next build.
- The Homebrew cask quits Marmot before an upgrade or uninstall, so the app is replaced cleanly.

## 4.1.0 (2026-11-11)

Safety and accuracy update.

**Safer cleaning**
- A folder that contains something on your Protected Paths list is now skipped as a whole, instead of taking the protected item to the Trash with it.
- Uninstalling a running app now waits until the app has actually quit. Time Capsule backups are tested before anything is removed, and cancelling the save dialog cancels the uninstall.
- Autopilot only cleans low-risk items, and only empties Trash items that have been there for 7 days or more.
- Leftover app data is checked with macOS before it's called orphaned, and build folders are only pre-selected when their project file is next to them.

**Undo you can count on**
- Every item is recorded in History the moment it's moved, so Undo works even if a clean is interrupted.
- Apps moved to the Trash through Finder can now be restored too. Results show which items can be undone.

**Honest numbers**
- Overlapping cleanup locations are counted once, so the total is no longer inflated.
- "Moved to Trash" and "Deleted" are shown separately, and emptying the Trash no longer counts the same space twice.
- Duplicates are confirmed byte for byte before they're shown.
- Disk Map no longer misplaces folders after one it can't read, and cancelled scans no longer affect Folder Trends.

## 4.0.2 (2026-11-10)

Updates the built-in updater to Sparkle 2.10.1, which includes security fixes.

Requires macOS 26. On macOS 13–15, use Marmot 3.2.0.

## 4.0.1 (2026-11-10)

Bug fixes and safety improvements.

- Duplicates now works in folders you add yourself, like an external drive. Each copy is checked byte for byte against the one you keep before it's removed.
- Build folders in ~/Documents/GitHub are cleaned instead of skipped.
- .iso files in Downloads are listed but no longer selected for you.
- App Updates finds more Sparkle updates and stops reporting ones that aren't real.
- Uninstalls stop if the app won't quit or the Time Capsule backup fails.
- Quitting an app before uninstalling no longer asks you where the app is.
- Clean Diagnostic Reports no longer says "Failed" when there's nothing to clean.
- Uninstall now moves system launch items to the Trash instead of deleting them.

Requires macOS 26. On macOS 13–15, use Marmot 3.2.0.

## 4.0.0 (2026-08-03)

#### 🦫 Marmot 4.0 — Liquid Glass

Marmot is rebuilt for macOS 26.

##### ✨ Liquid Glass
The floating layer — the ⌘K command palette, the drag-to-uninstall drop target, and the freed-space toast — now renders in Liquid Glass, with toolbars, sidebar, and sheets picking up the system material to match. Applied deliberately: glass belongs to the controls layer, so the dashboard cards and data tables keep their pastel washes, where legibility matters more than shine.

##### 🎨 Five themes, unchanged
Classic, Ocean, Bubblegum, Meadow, and Sorbet all work with the new material.

##### ⚠️ Requires macOS 26 (Tahoe) or later
This is the breaking change behind the 4.0 number.

**Running macOS 13–15?** You won't be offered this update — Marmot will never hand you a build it can't run. [Marmot 3.2.0](https://github.com/EPeiffer94/Marmot/releases/tag/v3.2.0) remains complete and fully supported: every tool, every safety guarantee, just without the glass.

##### Everything from 3.x, carried forward
Preview-first cleaning with dry runs and one-click Undo · the explainable health score with its full receipt · Startup Sentinel with suspicious-item detection · Disk Time Travel · Marmot Wrapped · drag-to-uninstall · a hardened safety gate with a hostile-path test suite.

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below.
Free forever. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 3.2.0 (2026-07-22)

#### 🦫 Marmot 3.2.0 — Sharper, faster, honester

##### 🗼 Sentinel got teeth
New launch items with suspicious traits — Apple impersonators in your LaunchAgents folder, programs running from /tmp or hidden dot-folders, plists pointing at missing binaries — now trigger a specific warning naming exactly what looks wrong. All deterministic, all explainable, never acted on without you.

##### ⚡ Faster where you feel it
- Scan results **survive navigation** — switch away from Disk Map, Duplicates, or Big Files and back, and your scan is still there
- App sizes in the Uninstaller appear **instantly on relaunch** (cached until the app updates)
- Duplicate hashing is easier on your disk and finishes faster

##### 🪞 Never choose a keeper blind
Every duplicate row has a **Peek** button — Quick Look the file before deciding which copy lives. And Marmot now learns from your keeper choices, gently favoring the folders you actually prefer.

##### 🗑️ Trash honesty
Trash-first cleaning frees nothing until the Trash empties — so Marmot now tells you when gigabytes it cleaned are still sitting there.

##### ✨ Also
Smart Scan and freed-this-week in the menu bar popover · live Full Disk Access status in onboarding · a What's New sheet after each update (like this one!) · disk-full warnings now point at the biggest wins.

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below. macOS 13+.
Free forever. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 3.1.0 (2026-07-21)

#### 🦫 Marmot 3.1.0 — Your Mac's health, explained

The health score is no longer a black box. Like everything in Marmot, it now shows its work:

##### 🧾 The health receipt
Live Status now displays exactly how the score is computed — every factor (CPU load, memory pressure, disk space, thermal state, battery) with its live reading and the precise points it's costing. "Health 82: memory pressure 85% used, −12." No other system monitor does this.

##### 🌡️ Thermal awareness
Marmot now watches your Mac's thermal state — the earliest warning sign of throttling. Warm, hot, or critical, you'll see it in the receipt and feel it in the score, usually before anything else looks wrong.

##### 📈 Live sparklines
CPU and memory cards carry a rolling 60-second history, so spikes are visible instead of vanishing between glances.

##### 🔔 Health alerts
New in Settings: get a notification when your health score drops below a threshold you choose — naming the exact factor responsible. At most one alert per 6 hours; off by default.

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below. macOS 13+.
Free forever. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 3.0.4 (2026-07-21)

#### 🦫 Marmot 3.0.4 — under the hood

No new buttons — just a healthier codebase:

- 🔩 All four disk scanners now share **one** hardened filesystem traversal, making a past class of scanning bug structurally impossible
- 🧹 Big views split into focused files; the three scan screens unified into one component (Duplicates gained rolling-digit progress everywhere)
- 🧪 Test suite reorganized into focused files — all 28 tests green

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below.
Free forever. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 3.0.3 (2026-07-21)

🚑 No more confusing Finder popup when an item needs Full Disk Access — Marmot now tells you exactly what to do instead.

## 3.0.2 (2026-07-21)

🛡️ Know before you clean — when a plan touches app containers that macOS protects, the preview now shows a Full Disk Access banner with a one-click jump to Settings, instead of failing afterward with cryptic errors

## 3.0.1 (2026-07-21)

🚑 Fixed: the Uninstaller now actually removes the app bundle. An over-strict safety-gate depth rule skipped /Applications/Name.app on every uninstall. Also: permission failures on app containers now tell you the fix (Full Disk Access) instead of showing raw AppleScript errors. Update recommended for everyone on 3.0.0.

## 3.0.0 (2026-07-21)

#### 🦫 Marmot 3.0 — the milestone release

Marmot started as "a cleaner that shows its work." Fifteen tools later, that promise runs deeper than ever. Everything from the 2.7–2.9 series, consolidated and polished:

##### 🗼 Startup Sentinel
Get notified **the day** something new starts launching at boot — not months later. Your own LaunchAgents folder (malware's favorite hiding spot) is watched in full.

##### 🎨 Multi-colored themes
Ocean, Bubblegum, Meadow, Sorbet — or the Classic mixed pastels. Every module re-dresses in the palette you pick. Never monochrome.

##### ⏪ Disk Time Travel & 🎁 Marmot Wrapped
Scrub your folder history and watch the treemap morph; share your cleaning year as a pastel stats card.

##### 🖱️ Frictionless by design
Drag any app onto the window or Dock icon to uninstall it. A visible drop target shows the way. After every clean: a freed-space toast with **one-click Undo**. Honest progress bars, ⌘1–⌘9 tool shortcuts, and Marmot reopens where you left off.

##### 🔒 Hardened
Strict POSIX quoting everywhere a filename touches a shell command, NUL-byte rejection in the safety gate, a hostile-path test suite on every CI run, and a public [threat model](https://github.com/EPeiffer94/Marmot/blob/main/SECURITY.md).

##### ♿ + 📸
VoiceOver support begins (treemap and change plans speak properly), and the README got real screenshots plus an honest comparison table.

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below. macOS 13+.
Free forever — no upsells, no license keys, no telemetry. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 2.8.2 (2026-07-20)

🎨 Make Marmot yours — the accent color in Settings now re-themes the entire app: every module tile, start screen, card, and button. The new Default swatch restores the classic mixed-pastel look.

## 2.8.1 (2026-07-20)

#### 🦫 Marmot 2.8.1

- 🎨 **Fixed: the accent color picker now actually applies.** A macOS quirk (KVO ignores dot-namespaced UserDefaults keys) meant your chosen pastel never reached the main window until relaunch. Pick a color in Settings and watch the Smart Scan and Review buttons follow, instantly — including in the standalone ⌘, Settings window.

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below.
Free forever. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 2.8.0 (2026-07-20)

#### 🦫 Marmot 2.8.0 — Sentinel

##### 🗼 Startup Sentinel
Marmot now watches your launch agent and daemon folders and **notifies you the day something new starts launching at boot** — not months later when you wonder why your Mac is slow. First run baselines silently; after that, any new background item gets a notification pointing you to Startup Items for review. Your own LaunchAgents folder (malware's favorite hiding spot) is watched in full. Toggle in Settings.

##### 🔒 Security hardening
- Every filename and app name spliced into a shell command now goes through strict POSIX quoting — a hostile filename can no longer break or inject into Time Capsule archives or launch-item removal commands.
- The safety gate now rejects NUL-byte path tricks, and a new hostile-path test suite hammers it with traversal, case, and encoding attacks on every CI run.
- New [SECURITY.md](https://github.com/EPeiffer94/Marmot/blob/main/SECURITY.md) documents the full threat model. Researchers welcome.

##### 🎨 Your Marmot, your pastel
Pick the app-wide accent color in Settings — six signature pastels, mint by default.

##### ♿ VoiceOver support begins
Treemap tiles and change-plan rows now speak properly: "Spotify cache, Low risk, 1.2 GB, selected."

##### 📸 Also
The README got real screenshots and an honest comparison table vs. CleanMyMac, AppCleaner, and DaisyDisk.

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below.
Free forever. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 2.7.2 (2026-07-20)

#### 🦫 Marmot 2.7.2 — Frictionless

A fit-and-finish pass to make Marmot a joy to use:

- 🎯 **Visible drop target** — drag an app over the window and you'll see it: "Drop to uninstall," with the promise of a full preview first.
- ↩️ **Undo, right there** — after a clean, a toast shows exactly what you freed with a one-click **Undo** that pulls everything back out of the Trash. No digging through History.
- 🧠 **Launch memory** — Marmot reopens on the section you last used, and **⌘1–⌘9** jump straight to any tool.
- 📊 **Honest progress** — Duplicates shows a real progress bar ("Comparing 214 of 1,032 candidates"); Big Files shows a live running total while it hunts. Cancelling a scan now returns you to the start screen instead of a false "nothing found."
- ⚖️ Also new in the README: an honest comparison table vs. CleanMyMac, AppCleaner, and DaisyDisk.

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below.
Free forever. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 2.7.1 (2026-07-17)

#### 🦫 Marmot 2.7.1 — Polish from user feedback

Two quality-of-life fixes reported by a user (thank you! 💚):

- 📌 **Steady menu bar** — the CPU % readout no longer shifts sideways when usage crosses from single to double digits. Single digits are now padded to a fixed width, so the menu bar stays perfectly still.
- 👀 **Clearer call to action** — after a scan, the next step is now obvious: the eye icon in **Duplicates**, **Cleanup**, and **Big Files** is now a prominent filled button with visible text ("Review & Remove…" / "Review Selected…"). Same safe preview-first flow, much easier to find.

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below.
Free forever. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 2.7.0 (2026-07-17)

#### 🦫 Marmot 2.7.0 — Time Travel Edition

Three features people will actually go nuts for:

##### ⏪ Disk Time Travel
Scrub through your folder's history with a timeline slider — watch the treemap morph as folders grow (pink) and shrink (green) over time. Hit play and watch weeks of disk usage animate before your eyes. Find it in **Disk Map** once a folder has been scanned more than once.

##### 🎁 Marmot Wrapped
Your cleaning year, wrapped. A shareable pastel stats card — total space freed, busiest tool, biggest single cleanup, Autopilot's contribution. Copy it as an image or save as PNG straight from the Dashboard report card. ✨

##### 🖱️ Drag-to-Uninstall
Drop any app onto the Marmot window **or its Dock icon** and jump straight to a full uninstall preview — bundle, caches, preferences, leftovers, all shown before anything moves.

##### Under the hood
- Folder history API in FolderTrends powering Time Travel
- Appcast generator now replaces same-version entries (no more duplicate-entry signing mixups like 2.6.0)

**Install:** `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below.
Free forever. If Marmot saved your disk, [tip the marmot ☕](https://ko-fi.com/kasakir)

## 2.6.0 (2026-07-17)

#### 🐿️ Marmot 2.6.0 — quietly smarter

No AI, no cloud, no guessing — Marmot just pays closer attention now.

##### 🧠 Smarter duplicate handling
The Duplicate Finder now picks the *sensible* copy to keep by default: the one in your Documents beats the one rotting in Downloads, and `report copy (2).pdf` never wins against `report.pdf`. Your choice always overrides — this just makes the default the one you'd have picked anyway.

##### 📋 It notices your habits
Cleaning manually every week? The Dashboard will gently point out that Autopilot exists and can do it for you on a schedule. It only speaks up after a real pattern (3+ separate cleaning days in a month) and goes quiet forever once you have a rule.

##### 🧾 Orphans get name tags
Leftover data from long-gone apps now shows *where it came from* when macOS's installer receipts can identify it: "Originally installed via package com.adobe.acrobat.reader." No more mystery ghosts.

##### 📦 Update
On 2.1+? **Check for Updates…** and you're done. ✨
New? `brew install --cask EPeiffer94/marmot/marmot` — or grab the zip below. macOS 13+.

---
💛 Free forever. Tip jar: [ko-fi.com/kasakir](https://ko-fi.com/kasakir) or Settings → Support.

## 2.5.0 (2026-07-17)

#### 🐿️ Marmot 2.5.0 — brew it, ask it, trust it

##### 🍺 Homebrew!

Marmot is now one command away:

```sh
brew install --cask EPeiffer94/marmot/marmot
```

##### 🪄 The palette got smart

**⌘K** now understands what you mean — entirely on your Mac, no AI cloud anything:

- Type **"big old videos"** → jumps to Big Files with size and age filters applied
- Type **"files over 2gb"** → same, your numbers respected
- Type **"uninstall slack"** or **"reset spotify"** → the app's removal or reset plan, one Enter away

##### 🔮 Space forecast

The Dashboard trends card now warns you *before* the disk fills: "At this pace, the disk could fill in about 23 days." It only speaks when the math is solid — no fortune telling.

##### 🧪 Under the hood

Ten new automated tests cover the forecast math, Autopilot scheduling, history aggregation, and the new query parser — all verified on every code change.

##### 📦 Update

On 2.1+? **Check for Updates…** does the rest. ✨ New? See the Homebrew one-liner above. Requires macOS 13+.

---
💛 Free forever. Tip jar: [ko-fi.com/kasakir](https://ko-fi.com/kasakir) or Settings → Support.

## 2.4.0 (2026-07-16)

#### 🐿️ Marmot 2.4.0 — how fast is your internet, anyway?

##### 🚀 Built-in speed test

New in **Live Status**: a lightweight internet speed test. One click measures your ping, download, and upload against Cloudflare's nearby servers — each direction runs for just ~8 seconds, adapts to any connection from DSL to gigabit, and never touches the network unless you ask.

##### ⚙️ Settings, finally findable

Settings now lives right in the sidebar (under Activity), opens inside the main window, and there's a gear button in the menu bar HUD that jumps straight to it. The classic ⌘, still works too — and the ⌘K palette knows the way.

##### 📦 Update

On 2.1+? Hit **Check for Updates…** and Marmot handles the rest. ✨
New here? Download, drag to Applications, one-time "Open Anyway" in System Settings → Privacy & Security. Requires macOS 13+.

---
💛 Marmot is free forever. If it's earned a coffee: [ko-fi.com/kasakir](https://ko-fi.com/kasakir) or Settings → Support in the app.

## 2.3.0 (2026-07-16)

#### 🐿️ Marmot 2.3.0 — the features other apps charge for

Four new tools in this release. Elsewhere, these cost money. Here, they're free — forever.

##### 🔄 App Reset
An app acting weird? Right-click it in the Uninstaller and choose **Reset** — Marmot clears its caches, preferences, and data while keeping the app installed. Like a factory reset, with the full preview-first treatment.

##### 📦 Time Capsule uninstalls
Flip the **Time Capsule** toggle in the Uninstaller and every uninstall first archives the app *and all its data* to a zip wherever you choose. Change your mind next month? Next year? It's all still there.

##### 🔍 Big Files
New in the sidebar: one scan finds every file over 100 MB in your home folder. Filter by size (up to 5 GB+) and age (6 months, 1 year), sort, select, and reclaim — that forgotten screen recording from 2024 is finally toast.

##### 🗼 Update Watchtower
Turn it on in Settings and Marmot quietly checks **all** your installed apps for updates daily or weekly, and notifies you when something's outdated. (Yes, there's a $15 app that does only this.)

##### 💛 Also new
Marmot now has a tip jar — Settings → Support, or [Ko-fi](https://ko-fi.com/kasakir). Completely optional; Marmot stays free forever, no upsells, no license keys.

##### 📦 Update
On 2.1+? Hit **Check for Updates…** and enjoy. ✨ New? Download, drag to Applications, one-time "Open Anyway" in Privacy & Security. macOS 13+.

## 2.2.0 (2026-07-15)

#### 🐿️ Marmot 2.2.0 — a fresh coat of pastel, twice as fast underneath

##### 🎨 A whole new look

Marmot got a makeover in soft pinks, greens, and blues:

- 🗂️ **Reorganized sidebar** — tools grouped into Clean, Apps, System, and Activity, each with its own colorful icon
- 🏠 **Prettier Dashboard** — pastel-washed cards for health, reclaimable space, suggestions, and trends
- ✨ **Friendlier scan screens** — every tool greets you with its own color and a clear one-button start
- 🌓 Looks great in both light and dark mode

##### ⚡ Much faster scanning

- 🗺️ **Disk Map** scans in roughly half the time — the scanner was rebuilt to read the disk in a single pass per folder tree, across all CPU cores
- 🪞 **Duplicate Finder** collects candidates dramatically faster
- 🚀 Snappier launch, and smarter about skipping background work that isn't needed

##### 📦 Update

Already on 2.1.x? Just hit **Check for Updates…** in Marmot — it updates itself. ✨
New here? Download the zip, drag to Applications, and approve the one-time "Open Anyway" in System Settings → Privacy & Security. Requires macOS 13+.

## 2.1.2 (2026-07-14)

#### 🐿️ Marmot 2.1.2

- 🎯 **App Updates accuracy** — Marmot no longer suggests App Store updates that the store won't actually offer you. It now respects each update's minimum macOS requirement (just like the App Store does) and checks your country's storefront
- 📝 Clearer hint text on App Store entries, since store version numbering can occasionally differ from an app's internal version

📦 Already on 2.1.x? Just hit **Check for Updates…** in Marmot. ✨

## 2.1.1 (2026-07-13)

#### 🐿️ Marmot 2.1.1

- 🛡️ **Autopilot safety refinement** — newly created rules now wait one full interval before their first scheduled run (never run immediately on creation). Use "Run Now" for an instant run
- 🤝 Added a contributor guide — want to add cache definitions or translate Marmot? See CONTRIBUTING.md
- 🔧 Leaner repository and pinned dependencies for reproducible builds

📦 **If you're on 2.1.0:** don't download anything — just open Marmot and hit **Check for Updates…** 🎉
📦 New here or on 2.0.0? Download the zip, drag to Applications, and this is the last manual install.

## 2.1.0 (2026-07-13)

#### 🐿️ Marmot 2.1.0 — Marmot updates itself now

**This is the last version you'll ever download by hand.** 🎉

From this release onward, Marmot checks for updates automatically and installs them in-app with one click — no more visiting this page, no more Gatekeeper dance for updates. Every update is cryptographically signed and verified before installing.

Check anytime via **Marmot menu → Check for Updates…**, in Settings, or through the ⌘K palette.

##### 📦 Install (one last time!)

Unzip, drag Marmot.app to Applications, replace the old copy. First launch of a fresh install: System Settings → Privacy & Security → **"Open Anyway"**. Upgrading from 2.0.0? Your rules, history, trends, and settings all carry over.

Requires macOS 13+.

## 2.0.0 (2026-07-13)

#### 🐿️ Marmot 2.0.0 — your Mac, on autopilot

The biggest release yet. Marmot doesn't just clean anymore — it watches, learns, and handles the routine stuff for you. Still free, still open source, still never touching a file without your say-so.

##### ⏱️ Autopilot

Write a cleaning rule once — *"clear browser caches weekly," "sweep developer junk monthly"* — and Marmot runs it on schedule, then tells you what it freed. Your rules, your categories, your cadence:

- Every run is **trash-first**, fully logged in History, and restorable
- Risky categories (build artifacts, orphaned data) aren't even eligible — those stay human-only
- Run any rule on demand, pause it, or edit it anytime

##### 📈 Storage Trends

Marmot now remembers every scan:

- A Dashboard chart of **disk usage and reclaimable junk over time**
- **"Since last scan"** movers — which categories grew, which shrank
- In the Disk Map: **folder-level "what grew"** — scan again next week and see *exactly* which folders ballooned. Finally an answer to "why is my disk suddenly full?"

##### 💡 Smart Suggestions

The Dashboard now leads with what's actually worth doing: an overstuffed cache, a 90%-full disk, apps untouched for a year, a crowded login, hidden Time Machine snapshots — each one click from its fix.

##### ⌨️ Command Palette

Press **⌘K** anywhere: type to jump to any tool, kick off a Smart Scan, or fire an Autopilot rule. Enter runs the top match.

##### 🕰️ Plus

- **Thin Time Machine snapshots** — new maintenance task that often reclaims tens of hidden GB
- Faster, cleaner codebase with automated linting on every change

##### 📦 Install

Unzip, drag Marmot.app to Applications (replace the old copy if upgrading — your history, rules, and settings carry over). First launch: macOS will balk (free software, not notarized) — click OK, then **System Settings → Privacy & Security → "Open Anyway"**. One time only. 🎉

Requires macOS 13+.

## 1.4.0 (2026-07-13)

#### 🐿️ Marmot 1.4.0 — undo, alerts, and an honest report card

##### ✨ What's new

- ↩️ **Undo from History** — Marmot now remembers where every trashed item went. Changed your mind? Hit **Restore** in the History tab and it goes right back
- 🔔 **Junk alerts** — pick a threshold in Settings and Marmot quietly checks every few hours, showing ⚠︎ in the menu bar *and* sending a notification when reclaimable junk piles up (once a day max, off by default)
- 📈 **Report card** — the Dashboard now shows space freed this week, this month, and all time, plus your biggest recent win
- 🖱️ **Right-click power** — in any change preview, right-click an item to **Reveal in Finder** or mark it **Never Touch This** (instantly protected forever)
- 🪞 **Smarter duplicates** — hardlinked copies of the same file no longer count as duplicates (removing one wouldn't free any space anyway)

##### 🛠️ Under the hood

- History log now trims itself so the app stays fast forever
- Automated code linting joins the test suite on every change
- Groundwork for translations — contributors can now add languages easily

##### 📦 Install

Unzip, drag Marmot.app to Applications (replace the old copy if upgrading). First launch: macOS will balk (free software, not notarized) — click OK, then **System Settings → Privacy & Security → "Open Anyway"**. One time only. 🎉

Requires macOS 13+.

## 1.3.0 (2026-07-10)

#### 🐿️ Marmot 1.3.0 — sturdier, sortable, and smarter about dry runs

##### ✨ Improvements

- 📊 **Sortable app list** — click any column in the Uninstaller (Name, Size, Last Used) to sort
- 👟 **Dry-run-first mode** — with "Suggest dry run before applying" enabled in Settings, the safe simulated run is now the first option whenever you apply a plan
- 🧹 **Under the hood** — a full code-quality pass: shared UI components, centralized settings, safer low-level file scanning, and a streamlined release pipeline

##### 🐛 Fixes

- Fixed folders reporting **0 bytes** in the fast scanner introduced in 1.2.0 (if your numbers look wrong, run Smart Scan once to refresh)

##### 📦 Install

Unzip, drag Marmot.app to Applications (replace the old copy if upgrading). First launch: macOS will balk (free software, not notarized) — click OK, then **System Settings → Privacy & Security → "Open Anyway"**. One time only. 🎉

Requires macOS 13+.

## 1.2.0 (2026-07-08)

#### 🐿️ Marmot 1.2.0 — a new home screen and a big speed boost

##### ✨ What's new

- 🏠 **Dashboard** — Marmot now opens to a home screen: your system health at a glance, a big **Smart Scan** button, how much space is reclaimable (with a colorful breakdown), and shortcuts to every tool
- 👋 **First-run welcome** — a short walkthrough explains how preview-first cleaning works and helps you grant Full Disk Access with one click
- 🎨 **A real app icon** — no more generic Dock icon!
- ⚡ **Much faster scanning** — file measurement was rewritten at a lower level and now uses all your CPU cores; the Disk Map in particular is dramatically quicker
- 🧠 **Instant numbers** — scan results are remembered between launches, so the app shows real figures immediately and refreshes quietly in the background
- 🗺️ **Smarter Disk Map** — blocks are now colored by file type (video, photos, archives, documents…), with a detail bar that follows your mouse
- ⌨️ **⌘R** rescans in every tool

##### 📦 Install

Unzip, drag Marmot.app to Applications. First launch: macOS will balk (free software, not notarized) — click OK, then **System Settings → Privacy & Security → "Open Anyway"**. One time only. 🎉

Requires macOS 13+. Upgrading? Just replace the old Marmot.app.

**Full Changelog**: https://github.com/EPeiffer94/Marmot/compare/v1.1.1...v1.2.0

## 1.1.1 (2026-07-07)

#### 🐿️ Marmot 1.1.1 — faster and sturdier

Same features as 1.1.0, meaningfully better under the hood:

- ⚡ **Faster scans** — cleanup categories and duplicate hashing now use all CPU cores
- 📉 **Lighter monitoring** — live stats read process info directly from the system instead of spawning helper processes every 2 seconds
- 🛡️ **Tested safety** — the rules that decide what can be deleted are now covered by an automated test suite, run on every code change
- 🧹 General code cleanup and concurrency fixes

##### 📦 Install

Unzip, drag Marmot.app to Applications. First launch: macOS will balk (free software, not notarized) — click OK, then **System Settings → Privacy & Security → "Open Anyway"**. One time only. 🎉

💡 Grant **Full Disk Access** for the deepest scan coverage. Requires macOS 13+.

## 1.1.0 (2026-07-07)

#### 🐿️ Marmot 1.1.0 — three new modules!

##### ✨ What's new

- ⏳ **Unused Apps** — see every app you haven't opened in 3, 6, or 12 months (real "last opened" dates from Spotlight), sorted by size, with one-click uninstall including all leftovers
- 🪞 **Duplicate Finder** — finds files with *identical content* (hash-verified, not just matching names) in Downloads, Documents, and Desktop. Star the copy you want to keep; the rest go to the Trash after the usual preview
- ⚡ **Startup Items** — every login item, launch agent, and daemon explained in plain English, with badges for things that run at login or stay always-running. Remove what you don't want for a faster boot

##### 🛠️ Fixes & improvements

- Uninstaller and App Updates now list apps instantly (sizes fill in as they're computed)
- Root-owned apps (installed via installer packages) can now be uninstalled — Marmot trashes them through Finder with the standard admin prompt
- Disk Map no longer hangs on OneDrive/iCloud/Google Drive folders (cloud placeholders are skipped; scan them explicitly via Choose Folder if you want)
- Maintenance tasks that don't exist on your macOS version (like `periodic`) are now hidden instead of failing
- Menu bar HUD rebuilt on AppKit — fixes a freeze at launch on newer macOS versions

##### 📦 Install

Unzip, drag Marmot.app to Applications. First launch: macOS will balk (free software, not notarized) — click OK, then **System Settings → Privacy & Security → "Open Anyway"**. One time only. 🎉

💡 Grant **Full Disk Access** for the deepest scan coverage. Requires macOS 13+.

## 1.0.0 (2026-07-07)

#### 🐿️ Marmot 1.0.0 — first release!

A free, open-source Mac cleaner that shows you everything before it touches anything.

**Install:** unzip, drag Marmot.app to Applications.

**First launch (one time):** macOS will say it can't verify the app — that's because Marmot is free community software, not notarized through Apple's paid program. Click OK, then go to **System Settings → Privacy & Security → "Open Anyway"**. That's it, forever. 🎉

💡 For full scan coverage, grant Marmot **Full Disk Access** in Privacy & Security.

**What's inside:** deep cleanup, smart uninstaller, app updates, disk map, maintenance tools, live system stats, and a menu bar HUD — with dry-run previews for everything.

Requires macOS 13+.
