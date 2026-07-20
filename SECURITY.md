# Security

Marmot deletes files for a living, so its security posture is the product. This document explains the threat model, the defenses, and how to report problems.

## Reporting a vulnerability

Open a [GitHub security advisory](https://github.com/EPeiffer94/Marmot/security/advisories/new) (preferred, private) or email the maintainer. Please don't open a public issue for anything exploitable. You'll get a response within a few days, credit in the release notes if you want it, and our sincere gratitude.

## Threat model

What Marmot defends against:

1. **Itself.** The biggest risk in any cleaner app is a bug that deletes the wrong thing. Every destructive action flows through one gate — `Engine/SafetyRules.isSafeToRemove` — which re-validates each path *at execution time*, independent of what any scanner produced. The gate fails closed: system areas, user content (Documents, Desktop, Photos, Mail, backups, media libraries), path traversal (`..`), NUL bytes, non-absolute paths, volume roots, and anything not strictly inside an explicit allowlist are all refused. Removals are trash-first and logged with their Trash location for restore.
2. **Hostile filenames.** Filenames and app names are attacker-controlled input (any app you install chooses its own name). Everywhere a path or name is spliced into a shell command, it passes through `Shell.quoted` (POSIX single-quote escaping) or `Shell.appleScriptString` — never raw interpolation.
3. **Malicious updates.** Self-updates use Sparkle 2 with EdDSA signing: the app ships the public key, every release is signed with the private key (held only by the maintainer, never in the repo), and Sparkle refuses unsigned or tampered downloads regardless of what the appcast or CDN serves.
4. **Privilege misuse.** Marmot never runs as root. The few admin tasks (system launch items, some maintenance commands) are labeled `admin` in the preview and go through the standard macOS authorization prompt via `do shell script … with administrator privileges` — the OS, not Marmot, holds the credentials.

What Marmot does *not* defend against: an attacker with the ability to run arbitrary code as your user can already do anything Marmot can. Marmot adds no privilege beyond what you approve.

## Data & network

- **No telemetry, no accounts, no analytics.** Marmot makes network requests only for the actions you invoke: update checks (GitHub), Homebrew/App Store version lookups (App Updates), and the speed test (Cloudflare).
- All state — history log, trends, rules, preferences — lives in `~/Library/Application Support/Marmot/` and `UserDefaults`. Nothing leaves your Mac.

## Verifying a release

Every release zip is EdDSA-signed for Sparkle (signature in `appcast.xml`) and its SHA-256 is pinned in the Homebrew cask. To check a download by hand:

```sh
shasum -a 256 Marmot-x.y.z.zip   # compare with packaging/homebrew/marmot.rb
```

## Scope notes for researchers

Interesting targets, in rough order of impact: `SafetyRules` bypasses (a path that passes the gate but escapes the allowlist on disk — symlink games count), quoting escapes in `Shell.quoted`/`appleScriptString`, plan items that execute without appearing in the preview, and Sparkle configuration mistakes. The test suite's `SafetyRulesTests` shows the tricks already covered.
