# 🐿️ Marmot

**A free, open-source Mac cleaner that shows you everything before it touches anything.**

Marmot cleans, uninstalls, analyzes, maintains, and monitors your Mac — all in one lightweight native app. Think CleanMyMac + AppCleaner + DaisyDisk + iStat Menus, except it's free, MIT-licensed, and *obsessively* transparent about what it's doing. 💛

Inspired by the wonderful [Mole CLI](https://github.com/tw93/mole), rebuilt from scratch in Swift/SwiftUI as a friendly GUI app.

---

## ✨ The big idea: look before you leap

Most cleaner apps ask you to trust them. Marmot doesn't want your trust — it wants to *show you*. 👀

Every single action in Marmot goes through a **Change Plan** first:

1. 📋 **Review** — see every file, folder, and command in a visual list with sizes, risk badges (🟢 low / 🟠 medium / 🔴 high), and plain-English explanations of what each thing is
2. 👁️ **Dry run** — hit "Dry Run" and Marmot *simulates* the whole plan. Nothing on your disk is touched. You get a full report of what *would* have happened
3. ✅ **Apply** — only after an explicit confirmation that spells out the consequences

And even then:

- 🗑️ **Trash-first** — removed files go to the Trash, so they're recoverable
- 🛡️ **Safety gate** — every path is re-checked at the moment of deletion against protected zones (Documents, Desktop, Photos, Mail, backups… always off-limits)
- 📖 **History** — everything Marmot does (dry runs included!) is logged, forever viewable in the History tab

---

## 🧰 What's inside

| | Module | What it does |
|---|---|---|
| ✨ | **Cleanup** | Deep-scans caches, logs, browser junk, developer clutter (DerivedData, npm/yarn/pip/cargo…), app caches (Spotify, Slack…), leftovers from deleted apps, old installers, and stale `node_modules` folders |
| 🗑️ | **Uninstaller** | Removes an app *plus* all its hidden friends — launch agents, preferences, containers, caches, saved state |
| ⬇️ | **App Updates** | Finds outdated apps via Homebrew, Sparkle feeds, and the App Store. One-click upgrades for Homebrew casks |
| ⏳ | **Unused Apps** | Flags apps you haven't opened in 3/6/12 months (via Spotlight metadata) with their footprint — one click to the uninstaller |
| 🪞 | **Duplicate Finder** | Finds files with identical content (hash-verified, not just matching names), you pick which copy to keep |
| 🗺️ | **Disk Map** | A colorful, clickable treemap of your disk. Zoom into folders, spot the space hogs, find files over 100 MB |
| ⚡ | **Startup Items** | Shows every login item, launch agent, and daemon in plain English — remove the ones slowing down your boot |
| 🔧 | **Maintenance** | Flush DNS, rebuild Spotlight, refresh Finder/Dock, clear font caches… each task shows its *exact commands* before running |
| 📊 | **Live Status** | Real-time CPU (per-core!), GPU, memory, disk I/O, network graphs, battery health, top processes, and an overall health score |
| 🎛️ | **Menu bar HUD** | Live CPU% in your menu bar — click it for a mini dashboard |
| 🕰️ | **History** | Every change and every dry run, searchable and filterable |

---

## 📦 Download (no Xcode needed)

Grab the latest `Marmot-x.x.x.zip` from the [**Releases page**](https://github.com/EPeiffer94/marmot/releases), unzip it, and drag **Marmot.app** into your **Applications** folder.

**First launch:** Marmot is free community software and isn't notarized through Apple's paid developer program, so macOS will balk the first time. Here's the one-time dance: 💃

1. Double-click Marmot → macOS says it can't verify the app. Click **Done/OK** (not "Move to Trash"!)
2. Open **System Settings → Privacy & Security**, scroll down, and click **"Open Anyway"** next to the Marmot message
3. Confirm once more — and that's it, forever. 🎉

<details>
<summary>Terminal alternative (one line)</summary>

```sh
xattr -cr /Applications/Marmot.app && open /Applications/Marmot.app
```
This clears the quarantine flag macOS puts on downloaded files.
</details>

## 🚀 Building from source

**You'll need:** macOS 13+ and Xcode (free on the App Store) or the full Swift toolchain.

```sh
git clone https://github.com/EPeiffer94/marmot.git
cd marmot
make run
```

That's it! 🎉 `make` builds `Marmot.app` in the project folder — drag it to `/Applications` if you'd like to keep it around.

### 🔐 Permissions: one grant, big difference

Give Marmot **Full Disk Access**: System Settings → Privacy & Security → Full Disk Access → **+** → add Marmot. This is a one-time thing and it's the single biggest upgrade you can give the app — it lets the scanners *see* protected areas like Mail data, Safari storage, and other apps' containers. Without it nothing breaks; those spots are just invisible and get skipped. 🙈

A few notes on how Marmot handles privileges:

- 🏠 **Most features need no special access at all** — caches, logs, leftovers, Trash, and app uninstalls are all within your own user account
- 🔑 **A handful of maintenance tasks need admin** (rebuilding Spotlight, purging memory, system launch daemons…) — these are labeled `admin` in the preview and use the standard macOS password dialog, per task, when you apply
- 🚫 **Marmot never runs as root** — macOS breaks GUI apps launched that way (they lose their permission grants), so like every serious Mac utility, Marmot asks for elevation only at the moment it's needed

---

## 🧭 A quick tour

### Your first cleanup 🧹

1. Open the **Cleanup** tab and hit **Scan My Mac**
2. Watch the categories fill in with how much space each one is hoarding
3. Check the ones you want and hit **Review Selected…**
4. In the preview: uncheck anything you want to keep, then hit **Dry Run** to see a full "what would happen" report — zero risk
5. Happy with it? **Apply for Real**. Files land in your Trash, so there's still an undo 😌

### Uninstalling an app 👋

Pick an app in the **Uninstaller** tab → **Uninstall…** → Marmot shows the app *and* every leftover it found, grouped by location. Same drill: review, dry-run, apply.

### Exploring your disk 🔍

**Disk Map** → **Scan Home Folder** (or pick any folder). Click blocks to zoom in, right-click to reveal in Finder or remove. The **Large Files** toggle lists everything over 100 MB.

### Keeping an eye on things 👀

The **Live Status** tab is your dashboard; the **menu bar HUD** is the always-on mini version. Toggle the HUD in Settings if you prefer a quieter menu bar.

---

## 🛡️ Safety, in plain words

- Marmot **never** deletes anything without showing you first. There is no code path around the preview. 🙅
- **High-risk items are never pre-checked.** You have to opt in.
- Anything needing admin rights is labeled `admin` and uses the standard macOS password prompt — no sneaky privilege stuff.
- Have a folder you never want touched? Add it in **Settings → Protected Paths** and it's invisible to every scanner.
- Still nervous? Just use **Dry Run** for everything. Forever. That's a totally valid lifestyle. 💙

---

## 🗂️ For the curious: project layout

```
Sources/Marmot/
  MarmotApp.swift          App entry: window, menu bar HUD, settings
  Models/ChangePlan.swift  The preview-first core (ChangePlan / ChangeItem)
  Engine/                  Scanners, safety rules, executor, stats sampling
  Views/                   SwiftUI — one view per module + the preview sheet
```

The one file to read first: `Engine/SafetyRules.swift` — the allow-list and protected zones that everything else obeys.

---

## 🤝 Contributing

Issues and PRs are very welcome! Good first contributions: new cleanup categories, more app-cache definitions, better orphan detection, localizations.

## 📜 License

MIT — free forever, no upsells, no license keys. 🎁

Not affiliated with Mole or mole.fit — feature inspiration lovingly credited to [tw93/Mole](https://github.com/tw93/mole).
