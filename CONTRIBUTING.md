# Contributing to Marmot 🐿️

Thanks for wanting to help! Marmot is a free, open-source Mac utility, and contributions of every size are welcome — from a one-line cache definition to a whole new module.

## Getting started

You'll need macOS 26+ and Xcode 26 (or the matching Swift toolchain).

```sh
git clone https://github.com/EPeiffer94/Marmot.git
cd Marmot
make run        # builds Marmot.app and launches it
swift test      # runs the safety-rule test suite (needs full Xcode)
```

CI runs `swift build`, `swift test`, and SwiftLint on every push — green checks required to merge.

> ⚠️ **Heads-up:** CI compiles with an older Swift than you may have locally. Prefer explicit loops over long chained generic expressions (`.map{}.filter{}.sorted{}` with tuples) — they can time out the older type checker.

## The one rule that matters: preview-first 🛡️

Marmot's entire identity is that **nothing destructive happens without the user seeing it first**. Every removal flows through:

1. A scanner produces `ChangeItem`s (never deletes anything itself)
2. They're wrapped in a `ChangePlan` (high-risk items auto-deselected)
3. `PlanPreviewView` shows the user everything, with dry-run available
4. `PlanExecutor` re-validates **every path** against `SafetyRules` at execution time, trash-first

If your PR adds a way to delete something, it must ride this pipeline. PRs that bypass it won't be merged, no matter how convenient. When in doubt, read `Engine/SafetyRules.swift` first — it's the constitution.

## Where things live

```
Sources/Marmot/
  Models/ChangePlan.swift   The preview-first core types
  Engine/                   Scanners, safety gate, executor, stores, samplers
  Views/                    SwiftUI — one file per module + shared Components
Tests/MarmotTests/          Safety-rule truth table + version comparison tests
```

## Easy wins (great first PRs)

- **New cleanup definitions** — know an app that hoards cache? Add one `Spec(...)` line to `CleanupScanner.scanAppCaches()`. Include the path and what the cache is.
- **Treemap file-type colors** — add extensions to `TreemapView.cellColor`.
- **Translations** — copy `Resources/en.lproj` to your language code and translate the strings you see in the app. Instructions inside the file.
- **Maintenance tasks** — new entries in `MaintenanceCatalog` (must include a `requiredBinary` check if the tool might not exist on all macOS versions).

## PR guidelines

- Keep PRs focused — one topic per PR
- `swift test` and `swiftlint` must pass (config is in `.swiftlint.yml`)
- Destructive operations: explain in the PR description how the change respects the preview-first pipeline
- New cleanup paths: be conservative — when unsure whether something is safe to remove, mark it `.medium` risk and `selected: false`

## Releases (maintainers)

See the "Self-updates" section of the README — `make release`, sign with `scripts/make-appcast-entry.sh`, push the appcast, attach the zip to a GitHub release.

## Questions?

Open a [Discussion](https://github.com/EPeiffer94/Marmot/discussions) or an issue. Be kind; we're all here because we like our Macs tidy. 💛
