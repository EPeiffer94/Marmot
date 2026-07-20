# Show HN draft

**Post when:** README screenshots are live, and ideally after notarization (fewer "it won't open" comments). Post Tuesday–Thursday, 8–10am ET. Stick around for the first 2–3 hours to answer comments — that's what keeps a post alive.

---

**Title:**

Show HN: Marmot – free, open-source Mac cleaner that shows every change before making it

**URL:** https://github.com/EPeiffer94/Marmot

**First comment (post this yourself immediately):**

Hi HN! I built Marmot because every Mac cleaner asks for blind trust — you click "Clean" and hope. Marmot inverts that: every destructive action goes through a Change Plan you can read (every file, size, risk level, plain-English reason), dry-run (full simulation, nothing touched), and only then apply. Removals are trash-first with one-click Undo, every path is re-validated against a safety allowlist at deletion time, and everything is logged and restorable.

It's 14 tools in one native SwiftUI app: cleanup, uninstaller with leftover hunting, duplicate finder (hash-verified), big-file hunter, disk treemap, scheduled cleaning rules, startup item manager, live system stats, and app update checking across Homebrew/Sparkle/App Store.

A few parts I enjoyed building:

- The safety gate is one function every deletion must pass at execution time, independent of what any scanner produced. It fails closed: system areas, Documents/Photos/Mail, path traversal, NUL bytes — refused. The test suite throws hostile paths at it.
- Disk scanning uses the raw fts(3) C API across all cores — size, inode, and mtime come free from the traversal, so a full home-folder map takes seconds.
- "Disk Time Travel": it snapshots folder sizes on every scan, so you can scrub a timeline and watch a treemap morph as folders grew and shrank.
- A new-startup-item sentinel that notifies you the day something installs a launch agent.

It's MIT-licensed, no telemetry, no account, free forever (there's a tip jar). Self-updates via Sparkle with EdDSA signing. macOS 13+.

`brew install --cask EPeiffer94/marmot/marmot`

Happy to answer anything about the safety design, fts performance, or SwiftUI-without-Xcode development.

---

**Prep checklist before posting:**

- [ ] Screenshots live in the README
- [ ] Notarized build shipped (or be ready for Gatekeeper questions — have the `xattr -cr` one-liner handy)
- [ ] AlternativeTo listing created (alternativeto.net → "Add app") so switch-searchers find it afterward
- [ ] Reply fast; be generous with technical detail; never argue
