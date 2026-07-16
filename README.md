# 🐿️ Marmot

**A free, open-source Mac cleaner that shows you everything before it touches anything.**

Marmot cleans, uninstalls, automates, analyzes, and monitors your Mac — fourteen tools in one lightweight native app, dressed in friendly pastels. Think CleanMyMac + AppCleaner + DaisyDisk + iStat Menus + MacUpdater, except it's free, MIT-licensed, self-updating, and *obsessively* transparent about what it's doing. 💛

Inspired by the wonderful [Mole CLI](https://github.com/tw93/mole), rebuilt from scratch in Swift/SwiftUI.

---

## 📦 Download (no Xcode needed)

Grab the latest `Marmot-x.x.x.zip` from the [**Releases page**](https://github.com/EPeiffer94/Marmot/releases), unzip, and drag **Marmot.app** into **Applications**. From then on it updates itself — signed, verified, one click.

**First launch only:** Marmot is free community software, not notarized through Apple's paid program, so macOS balks once. Double-click Marmot → click **OK** (not "Move to Trash"!) → **System Settings → Privacy & Security → "Open Anyway"** → confirm. That's the whole dance, forever. 💃

<details>
<summary>Terminal alternative (one line)</summary>

```sh
xattr -cr /Applications/Marmot.app && open /Applications/Marmot.app
```
</details>

---

## ✨ The big idea: look before you leap

Most cleaner apps ask for your trust. Marmot shows its work instead. 👀

Every destructive action goes through a **Change Plan**:

1. 📋 **Review** — every file, folder, and command in a visual list with sizes, risk badges (🟢🟠🔴), and plain-English explanations
2. 👁️ **Dry run** — simulate the whole plan; nothing on disk is touched, you get a full "would have happened" report
3. ✅ **Apply** — only after a confirmation that spells out the consequences

And even then: removals are **trash-first** (recoverable — and restorable straight from the History tab), every path is **re-validated at deletion time** against protected zones (Documents, Photos, Mail, backups… always off-limits), and everything is **logged**. Right-click any item in a preview to reveal it in Finder or mark it *Never Touch This*.

---

## 🧰 What's inside

**🏠 Dashboard** — system health, reclaimable space with one-button **Smart Scan**, storage trends over time, and a suggestions feed that connects the dots ("12 GB of developer junk", "3 apps untouched for a year"). Press **⌘K** anywhere for the command palette.

### Clean

| | | |
|---|---|---|
| ✨ | **Cleanup** | Caches, logs, browser junk, developer clutter, app caches, leftovers from deleted apps, old installers, stale `node_modules` |
| ⏱️ | **Autopilot** | Write cleaning rules once — *"browser caches weekly"* — and Marmot runs them on schedule, trash-first, logged, announced |
| 🪞 | **Duplicates** | Identical-content files (hash-verified, hardlink-aware); you pick the keeper |
| 🔍 | **Big Files** | Every file over 100 MB in your home folder, filterable by size and age — find the forgotten 4 GB screen recording |

### Apps

| | | |
|---|---|---|
| 🗑️ | **Uninstaller** | App + all its hidden friends: launch agents, preferences, containers, caches. **Reset** clears an app's data without uninstalling; **Time Capsule** archives everything to a zip first, making uninstalls reversible forever |
| ⏳ | **Unused Apps** | Apps unopened for 3/6/12 months (real Spotlight data) with their footprint |
| ⬇️ | **App Updates** | Outdated apps via Homebrew, Sparkle feeds, and the App Store — plus **Watchtower**, which checks in the background and notifies you |

### System

| | | |
|---|---|---|
| 🗺️ | **Disk Map** | Clickable treemap colored by file type, with "since last scan: Movies +12 GB" folder diffing |
| ⚡ | **Startup Items** | Every login item, agent, and daemon in plain English — trim your boot |
| 🔧 | **Maintenance** | Flush DNS, rebuild Spotlight, thin Time Machine snapshots… each task shows its *exact commands* first |
| 📊 | **Live Status** | Per-core CPU, GPU, memory, disk I/O, network graphs, battery health — plus a built-in **internet speed test** |
| 🎛️ | **Menu bar HUD** | Live CPU% up top; click for a mini dashboard, junk alerts included |
| 🕰️ | **History** | Every change and dry run, filterable — with one-click **Restore** from the Trash |

> 💡 Several of these — App Reset, background update watching, scheduled cleaning, time-capsule uninstalls — are paid features elsewhere. Here they're just… features.

---

## 🧭 Your first five minutes

1. **Dashboard → Smart Scan** — see what's reclaimable, with a colorful breakdown
2. **Review Selected…** in Cleanup — uncheck anything, hit **Dry Run** for a zero-risk rehearsal, then apply. Files land in the Trash, and History can restore them
3. **Big Files** — one scan, sort by size, gasp
4. Grant **Full Disk Access** when you're ready (System Settings → Privacy & Security): one-time, and it lets the scanners see protected corners like Mail and other apps' containers. Without it nothing breaks — those spots are just skipped

---

## 🛡️ Safety, in plain words

- There is **no code path around the preview**. None. 🙅
- High-risk items are never pre-checked; risky categories aren't even eligible for Autopilot
- Admin-needing tasks are labeled `admin` and use the standard macOS password prompt
- Your own no-go folders: **Settings → Protected Paths**
- Marmot **never runs as root**, and never phones home — the only network calls are the ones you ask for (update checks, speed test)
- Still nervous? Dry Run everything, forever. Totally valid lifestyle. 💙

---

## 🔄 Self-updates

Since 2.1.0, Marmot updates itself via [Sparkle](https://sparkle-project.org): it checks this repo's appcast and cryptographically verifies every update against the project's EdDSA key before installing.

<details>
<summary>Release process (maintainers)</summary>

```sh
make release VERSION=x.y.z
sh scripts/make-appcast-entry.sh Marmot-x.y.z.zip x.y.z
git add -A && git commit -m "Release x.y.z" && git push
git tag vx.y.z && git push origin vx.y.z
# create the GitHub release, attach the zip (exact filename)
```

The signing key lives in the maintainer's Keychain — keep an exported backup safe.
</details>

---

## 🚀 Building from source

macOS 13+ and Xcode (free) or the full Swift toolchain:

```sh
git clone https://github.com/EPeiffer94/Marmot.git
cd Marmot
make run
```

```
Sources/Marmot/
  Models/ChangePlan.swift  The preview-first core
  Engine/                  Scanners, safety gate, executor, autopilot, stats
  Views/                   SwiftUI — one file per tool + shared components
```

Read `Engine/SafetyRules.swift` first — it's the constitution everything else obeys. CI runs build + tests + SwiftLint on every push.

---

## 🤝 Contributing

PRs and issues welcome — [CONTRIBUTING.md](CONTRIBUTING.md) has setup, architecture, and the preview-first ground rule. Easy first wins: new app-cache definitions (one line!), treemap colors, translations 🌍 (copy `Resources/en.lproj` to your language and follow the instructions inside).

## 💛 Support Marmot

Free forever — no upsells, no license keys, staying that way. If Marmot saved you gigabytes: ⭐ star the repo, [buy a coffee on Ko-fi](https://ko-fi.com/kasakir), [sponsor on GitHub](https://github.com/sponsors/EPeiffer94), or tell a friend with a full disk. Tip jar's in the app too: **Settings → Support**.

## 📜 License

MIT. 🎁 Not affiliated with Mole or mole.fit — feature inspiration lovingly credited to [tw93/Mole](https://github.com/tw93/mole).
