#!/bin/bash
# One-command Marmot release: checks, version bump, build, signing, GitHub
# release, in-app release notes, Homebrew cask and CHANGELOG.md.
#
#   make ship                 patch release   (4.1.0 -> 4.1.1)
#   make ship BUMP=minor      minor release   (4.1.0 -> 4.2.0)
#   make ship BUMP=major      major release   (4.1.0 -> 5.0.0)
#   make ship BUMP=4.3.0      exact version
#   make ship DRY=1           every check + draft notes; changes nothing
#   make ship RESUME=1        finish a release that stopped partway
#
# Or double-click "scripts/Release Marmot.command" in Finder.
#
# Order matters and is enforced here: the tag and the GitHub release (with
# the zip) go up BEFORE main is pushed, because pushing main publishes the
# appcast, and users must never be offered an update with no download.
set -Eeuo pipefail
# Parse the whole file with the bash that's running it (macOS ships 3.2)
# before doing anything, so a syntax problem can't stop a release halfway.
"$BASH" -n "$0" || { echo "release.sh has a syntax error for this bash ($BASH_VERSION)."; exit 1; }
cd "$(dirname "$0")/.."
# Finder/Terminal launches can miss Homebrew's folder (where gh lives) and
# ~/.local/bin (where Claude Code's installer puts `claude`).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH:$HOME/.local/bin"

BUMP="${1:-patch}"
MODE="${2:-}"            # "", "dry" or "resume"
REPO="Kasakir-AI/Marmot"
FEED="https://raw.githubusercontent.com/Kasakir-AI/Marmot/main/appcast.xml"
OLD_FEED="https://raw.githubusercontent.com/EPeiffer94/Marmot/main/appcast.xml"
TAP_RAW="https://raw.githubusercontent.com/Kasakir-AI/homebrew-marmot/main/Casks/marmot.rb"
TAP_DIR="../homebrew-marmot"
EXPECTED_EMAIL="214017273+Kasakir-AI@users.noreply.github.com"
STATE=".build/release-state"   # line 1: "version X.Y.Z", then one finished step per line
STEP="checks"
mkdir -p .build

say()  { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

step_done() { [ -f "$STATE" ] && grep -qx "$1" "$STATE"; }
makefile_version() { grep '^VERSION' Makefile | head -1 | sed 's/.*= *//'; }

on_error() {
    # Command substitutions inherit this trap; only the main script reports.
    [ "${BASH_SUBSHELL:-0}" -eq 0 ] || return 0
    trap - ERR
    printf '\n\033[31m✗ Release stopped during: %s\033[0m\n' "$STEP" >&2
    if [ ! -f "$STATE" ]; then
        printf 'Nothing was changed. Fix the problem above and run it again.\n' >&2
        return 0
    fi
    if step_done push_main; then
        printf 'The update is already live for users; only the remaining steps are unfinished.\n' >&2
    else
        printf 'Users are not offered the update yet.\n' >&2
    fi
    printf 'Fix the problem above, then finish with:\n  cd ~/Claude/Projects/"MacOS app"\n  make ship RESUME=1\n' >&2
}
trap on_error ERR

die() {
    printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2
    on_error
    exit 1
}

# Runs step NAME once: skipped when a resumed release already finished it.
run_step() {
    local name="$1" label="$2"
    STEP="$label"
    if step_done "$name"; then
        ok "$label: already done"
        return 0
    fi
    say "$label"
    "do_$name"
    echo "$name" >> "$STATE"
}

# True once URL serves text containing PATTERN (GitHub's cache can lag).
eventually() {
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        if curl -fsSL "$1?nocache=$(date +%s)" 2>/dev/null | grep -qF "$2"; then return 0; fi
        sleep 10
    done
    return 1
}

# Drafts release notes from merged pull requests (titles, with their
# descriptions as reference) plus commits pushed straight to main.
draft_notes() {
    local prev since=""
    prev=$(git describe --tags --abbrev=0 2>/dev/null || true)
    [ -n "$prev" ] && since=$(git log -1 --format=%cI "$prev")
    git log --no-merges --format='%H%x09%s' ${prev:+"$prev"..HEAD} > .build/notes-commits.tsv
    gh pr list --repo "$REPO" --state merged --base main --limit 100 \
        --json number,title,body,mergedAt,commits > .build/notes-prs.json 2>/dev/null \
        || echo "[]" > .build/notes-prs.json
    python3 - "$NEW" "$since" <<'PY'
import json, re, sys
from datetime import datetime

new, since = sys.argv[1], sys.argv[2]
def ts(s): return datetime.fromisoformat(s.replace("Z", "+00:00"))

prs = json.load(open(".build/notes-prs.json"))
if since:
    cut = ts(since)
    prs = [p for p in prs if p.get("mergedAt") and ts(p["mergedAt"]) > cut]
prs.sort(key=lambda p: p["number"])
pr_shas = {c.get("oid") for p in prs for c in p.get("commits") or []}
pr_numbers = {p["number"] for p in prs}

skip = re.compile(r"^(Release \d|Bump version)")
commits = []
for line in open(".build/notes-commits.tsv"):
    sha, _, subject = line.rstrip("\n").partition("\t")
    if not subject or skip.match(subject) or sha in pr_shas:
        continue
    squashed = re.search(r"\(#(\d+)\)$", subject)
    if squashed and int(squashed.group(1)) in pr_numbers:
        continue
    commits.append(subject)

out = [f"<!-- Draft notes for Marmot {new}. Rewrite them for users: what changed and why it matters. -->",
       "<!-- Lines starting with <!-- are removed before publishing. Save and close TextEdit when done. -->",
       ""]
out += [f"- {p['title']}" for p in prs] + [f"- {c}" for c in commits]
if not prs and not commits:
    out.append("- ")
if prs:
    out += ["", "<!-- For reference, the pull request descriptions: -->"]
    for p in prs:
        out.append(f"<!-- #{p['number']} {p['title']} -->")
        for l in (p.get("body") or "").splitlines()[:40]:
            l = l.replace("-->", "→").strip()
            if l:
                out.append(f"<!--     {l} -->")
print("\n".join(out))
PY
}

# Prints the version after CURRENT for BUMP (patch/minor/major/x.y.z).
# (Kept out of $( ) on purpose: macOS's bash 3.2 misparses heredocs there.)
next_version() {
    python3 - "$1" "$2" <<'PY'
import re, sys
cur, bump = sys.argv[1], sys.argv[2]
parts = [int(p) for p in cur.split(".")]
if bump == "patch":   new = [parts[0], parts[1], parts[2] + 1]
elif bump == "minor": new = [parts[0], parts[1] + 1, 0]
elif bump == "major": new = [parts[0] + 1, 0, 0]
elif re.fullmatch(r"\d+\.\d+\.\d+", bump): new = [int(p) for p in bump.split(".")]
else: sys.exit(f"Not a version: {bump!r} (use patch, minor, major, or e.g. 4.2.0)")
if new <= parts: sys.exit("{} is not newer than {}".format(".".join(map(str, new)), cur))
print(".".join(map(str, new)))
PY
}

# Rewrites the draft (file $1) into plain-language notes for users, using
# Claude Code's command-line tool and your Claude login. Prints the notes;
# fails (so the caller falls back to the draft) if Claude Code isn't
# installed or signed in, takes over 5 minutes, or returns something odd.
rewrite_notes() {
    local draft="$1" dir
    command -v claude >/dev/null 2>&1 || return 1
    dir=$(mktemp -d)
    {
        cat <<'TXT'
You write the release notes for Marmot, a free Mac app that cleans up disk space safely. The readers are ordinary Mac users, not developers.

Below are the raw changes in this release (pull request titles and descriptions, and commit messages), and the previous release's notes as an example of the style to match.

Rules:
- Plain, everyday language. Short sentences. Say what changed and why it matters to the user.
- Only include changes a user could notice: new features, fixes, safety, speed, wording.
- Leave out internal work: tests, CI, release scripts, refactoring, developer docs, and dependency updates that don't change anything a user sees.
- Never invent or exaggerate. If you can't tell what a change means for users, leave it out.
- Format: one short summary sentence, then a "- " bullet per change. Only if there are more than 5 bullets, group them under short **bold** headings.
- No emoji, no marketing words (exciting, seamless, powerful, game-changing), no "we're thrilled".
- If nothing in this release is user-facing, write exactly: Behind-the-scenes improvements to keep Marmot reliable. Nothing changes in how you use it.
- Output only the release notes in Markdown. Nothing before or after them.
TXT
        echo ""
        echo "<previous_release_notes>"
        awk '/^## /{n++} n==1' CHANGELOG.md 2>/dev/null | tail -n +2
        echo "</previous_release_notes>"
        echo ""
        echo "<changes>"
        cat "$draft"
        echo "</changes>"
    } > "$dir/prompt.txt"
    # Runs in an empty folder so nothing from this repo is loaded, with no
    # tool permissions: it only reads the text piped in and writes notes.
    if ! (cd "$dir" && perl -e 'alarm shift @ARGV; exec @ARGV' 300 \
            claude -p "Write the release notes as instructed in the input." \
            --permission-mode dontAsk --output-format text \
            < prompt.txt > notes.md 2> error.log); then
        rm -rf "$dir"
        return 1
    fi
    if ! python3 - "$dir/notes.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read().strip()
text = re.sub(r"^```[a-z]*\n|\n```$", "", text).strip()          # stray code fences
lines = text.splitlines()
if lines and re.match(r"^(here|sure|okay)\b", lines[0], re.I):    # stray preamble
    text = "\n".join(lines[1:]).strip()
if not re.search(r"[A-Za-z]", text) or "<!--" in text or len(text) > 6000:
    sys.exit(1)
print(text)
PY
    then
        rm -rf "$dir"
        return 1
    fi
    rm -rf "$dir"
}

show_notes() {
    echo ""
    sed 's/^/    /' "$1"
    echo ""
}

# ---------------------------------------------------------------- checks
say "Checking everything before changing anything"

[ "$(uname)" = "Darwin" ] || die "Run this on your Mac."
for tool in git gh swift make ditto shasum curl python3 unzip; do
    command -v "$tool" >/dev/null || die "Missing tool: $tool$([ "$tool" = gh ] && echo ' (install it with: brew install gh)')"
done
ok "Tools present"

gh auth status >/dev/null 2>&1 || die "GitHub CLI isn't signed in. Run: gh auth login"
LOGIN=$(gh api user --jq .login)
[ "$(echo "$LOGIN" | tr '[:upper:]' '[:lower:]')" = "kasakir-ai" ] \
    || die "GitHub CLI is signed in as $LOGIN, not Kasakir-AI."
ok "GitHub CLI signed in as $LOGIN"

[ "$(git config user.email || true)" = "$EXPECTED_EMAIL" ] \
    || die "Commits would not use your no-reply email. Run: git config user.email $EXPECTED_EMAIL"
[ -d "$TAP_DIR/.git" ] || die "Homebrew tap not found at $TAP_DIR"
[ "$(git -C "$TAP_DIR" config user.email || true)" = "$EXPECTED_EMAIL" ] \
    || die "Homebrew tap commits would not use your no-reply email. Run: git -C $TAP_DIR config user.email $EXPECTED_EMAIL"
ok "Commits in both repos will use your GitHub no-reply email"

[ "$(git branch --show-current)" = "main" ] || die "Switch to main first: git switch main"
[ "$(git -C "$TAP_DIR" branch --show-current)" = "main" ] || die "The Homebrew tap folder isn't on main."
git fetch -q origin --tags

if [ "$MODE" = "resume" ]; then
    [ -f "$STATE" ] || die "There's no unfinished release to resume."
    NEW=$(head -1 "$STATE" | sed 's/^version //')
    git merge-base --is-ancestor origin/main main \
        || die "GitHub's main has commits your Mac doesn't. Sort that out first."
    OTHER=$(git status --porcelain | grep -v -E ' (appcast\.xml|packaging/homebrew/marmot\.rb|CHANGELOG\.md)$' || true)
    [ -z "$OTHER" ] || die "Unexpected uncommitted changes:
$OTHER"
    ok "Resuming the release of Marmot $NEW"
else
    if [ -f "$STATE" ]; then
        die "Marmot $(head -1 "$STATE" | sed 's/^version //') was only partly released. Finish it first."
    fi
    [ -z "$(git status --porcelain)" ] || die "Uncommitted changes. Commit or stash them first:
$(git status --short)"
    if [ "$(git rev-parse main)" != "$(git rev-parse origin/main)" ]; then
        if git merge-base --is-ancestor main origin/main; then
            git merge -q --ff-only origin/main
            ok "Pulled the latest main from GitHub"
        elif git merge-base --is-ancestor origin/main main; then
            die "Your Mac has commits that aren't on GitHub yet. Push them and let CI pass first: git push"
        else
            die "Your main and GitHub's main have diverged. Sort that out first."
        fi
    else
        ok "main is up to date with GitHub"
    fi

    CURRENT=$(makefile_version)
    NEW=$(next_version "$CURRENT" "$BUMP") || die "Bad version."
    ok "Version $CURRENT → $NEW"

    if git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null \
        || [ -n "$(git ls-remote --tags origin "refs/tags/v$NEW")" ]; then
        die "Tag v$NEW already exists."
    fi
    if gh release view "v$NEW" --repo "$REPO" >/dev/null 2>&1; then
        die "GitHub release v$NEW already exists."
    fi
    ok "v$NEW is unused"

    HEAD_SHA=$(git rev-parse HEAD)
    RUN_ID=$(gh run list --repo "$REPO" --workflow CI --commit "$HEAD_SHA" --limit 1 \
        --json databaseId --jq '.[0].databaseId // empty')
    [ -n "$RUN_ID" ] || die "No CI run found for the current commit. Push main and let CI finish first."
    if [ "$(gh run view "$RUN_ID" --repo "$REPO" --json status --jq .status)" != "completed" ]; then
        echo "  CI is still running; waiting for it…"
        gh run watch "$RUN_ID" --repo "$REPO" --exit-status >/dev/null || die "CI failed on the current commit."
    fi
    [ "$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion --jq .conclusion)" = "success" ] \
        || die "CI didn't pass on the current commit: https://github.com/$REPO/actions/runs/$RUN_ID"
    ok "CI passed on the commit being released"

    [ -z "$(git -C "$TAP_DIR" status --porcelain)" ] || die "The Homebrew tap folder has uncommitted changes."
    git -C "$TAP_DIR" pull -q --ff-only
    ok "Homebrew tap is clean and up to date"
fi

TAG="v$NEW"
ZIP="Marmot-$NEW.zip"
DRAFT=".build/release-notes-$NEW.draft.md"   # raw: PR titles, commits
NOTES=".build/release-notes-$NEW.md"         # what will be published (before confirming)
FINAL=".build/release-notes-$NEW.final.md"   # locked in once you confirm
NOTES_FOR=".build/release-notes-$NEW.commit" # the commit the notes describe

# Build now, before anything changes, so a broken build never leaves a
# pushed version bump behind. The real build later reuses this work.
if ! step_done build; then
    swift build -c release > .build/preflight-build.log 2>&1 \
        || die "The app doesn't build. Details: .build/preflight-build.log"
    ok "The app builds"
fi

# Test-sign a scratch file, so a missing key stops us here and not halfway.
if ! step_done appcast; then
    SIGN=$(find .build/artifacts -name sign_update -type f 2>/dev/null | head -1)
    [ -n "$SIGN" ] || die "Sparkle's sign_update tool is missing. Run: swift package resolve"
    PROBE=$(mktemp)
    echo "signing check" > "$PROBE"
    if ! "$SIGN" "$PROBE" >/dev/null 2>&1; then
        rm -f "$PROBE"
        die "The Sparkle signing key isn't in your Keychain (or access was denied). Restore it from your backup first."
    fi
    rm -f "$PROBE"
    ok "Sparkle signing key works"
fi

# ---------------------------------------------------------------- notes
if [ ! -s "$FINAL" ]; then
    # Write notes unless there are some already for this exact commit. An
    # unedited raw draft (Claude Code was unavailable) is retried, and notes
    # from an earlier run are rewritten once new commits have landed.
    if [ -s "$NOTES" ] && [ "$(cat "$NOTES_FOR" 2>/dev/null)" != "$(git rev-parse HEAD)" ]; then
        warn "There are new commits since these notes were written, so they're being rewritten."
        rm -f "$NOTES"
    fi
    if [ ! -s "$NOTES" ] || { grep -q '^<!-- Draft notes' "$NOTES" \
            && { [ ! -s "$DRAFT" ] || cmp -s "$NOTES" "$DRAFT"; }; }; then
        draft_notes > "$DRAFT"
        say "Writing release notes for users (Claude Code)"
        if rewrite_notes "$DRAFT" > "$NOTES.tmp"; then
            mv "$NOTES.tmp" "$NOTES"
            ok "Written"
        else
            rm -f "$NOTES.tmp"
            cp "$DRAFT" "$NOTES"
            if command -v claude >/dev/null 2>&1; then
                warn "Claude Code couldn't write them (is it signed in? run: claude). Using the raw draft."
            else
                warn "Claude Code isn't installed, so here's the raw draft to rewrite yourself."
            fi
        fi
    fi
    git rev-parse HEAD > "$NOTES_FOR"
    say "Release notes (GitHub release, in-app update window and CHANGELOG.md)"
    show_notes "$NOTES"
    if grep -q '^<!--' "$NOTES"; then
        open -e "$NOTES"
        echo "  This is the raw draft. TextEdit opened it: rewrite it for users, save, and close the window."
    fi
fi

if [ "$MODE" = "dry" ]; then
    trap - ERR
    say "Dry run finished: every check passed. Nothing was changed."
    echo "  The draft notes stay in $NOTES for the real run."
    exit 0
fi

echo ""
while :; do
    if [ "$MODE" = "resume" ]; then
        read -r -p "  Type $NEW to continue releasing it (anything else stops): " CONFIRM
    elif [ -s "$FINAL" ]; then
        read -r -p "  Type $NEW to release it (anything else cancels): " CONFIRM
    else
        read -r -p "  Type $NEW to release it, e to edit the notes first (anything else cancels): " CONFIRM
    fi
    [ "$CONFIRM" = "e" ] && [ ! -s "$FINAL" ] && [ "$MODE" != "resume" ] || break
    open -e "$NOTES"
    read -r -p "  Edit the notes in TextEdit, save, close the window, then press Return: " _
    show_notes "$NOTES"
done
if [ "$CONFIRM" != "$NEW" ]; then
    trap - ERR
    if [ -f "$STATE" ]; then echo "Stopped. Finish later with: make ship RESUME=1"
    else echo "Cancelled. Nothing was changed."; fi
    exit 0
fi

if [ ! -s "$FINAL" ]; then
    { grep -v '^[[:space:]]*<!--' "$NOTES" || true; } | sed '/./,$!d' > "$FINAL"
    if ! grep -q '[[:alnum:]]' "$FINAL"; then
        rm -f "$FINAL"
        die "The release notes are empty."
    fi
fi
[ -f "$STATE" ] || echo "version $NEW" > "$STATE"

# ---------------------------------------------------------------- steps
do_bump() {
    if [ "$(makefile_version)" != "$NEW" ]; then
        python3 - "$NEW" <<'PY'
import re, sys
s = open("Makefile").read()
s, n = re.subn(r"^VERSION = .*$", f"VERSION = {sys.argv[1]}", s, count=1, flags=re.M)
assert n == 1
open("Makefile", "w").write(s)
PY
        git commit -q -am "Bump version to $NEW"
    fi
    git push -q origin main   # safe: the appcast is unchanged, nobody is offered anything
    ok "Committed and pushed"
}

do_build() {
    local plist build
    make release > .build/release-build.log 2>&1 || die "The build failed. Details: .build/release-build.log"
    build=$(git rev-list --count HEAD)
    plist=$(mktemp)
    unzip -p "$ZIP" "Marmot.app/Contents/Info.plist" > "$plist"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$NEW" ] \
        || die "The zip has the wrong version."
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$build" ] \
        || die "The zip has the wrong build number."
    rm -f "$plist"
    ok "Built $ZIP: version $NEW, build $build"
}

do_appcast() {
    NOTES_FILE="$FINAL" sh scripts/make-appcast-entry.sh > /dev/null
    ok "Feed entry signed, with release notes for the update window"
}

do_cask() {
    sh scripts/make-cask.sh > /dev/null
    ok "Cask updated"
}

do_changelog() {
    python3 - "$NEW" "$FINAL" <<'PY'
import datetime, os, re, sys
new, notes_path = sys.argv[1], sys.argv[2]
path = "CHANGELOG.md"
text = open(path).read() if os.path.exists(path) else (
    "# Changelog\n\nEvery Marmot release, newest first. Downloads are on "
    "[GitHub Releases](https://github.com/Kasakir-AI/Marmot/releases).\n")
if re.search(rf"^## {re.escape(new)}\b", text, re.M):
    sys.exit(0)  # already added (resumed release)
notes = open(notes_path).read().strip()
notes = re.sub(r"^(#{1,4})(\s)", r"##\1\2", notes, flags=re.M)  # keep version headings on top
entry = f"## {new} ({datetime.date.today().isoformat()})\n\n{notes}\n\n"
first = re.search(r"^## ", text, re.M)
text = text[:first.start()] + entry + text[first.start():] if first else text.rstrip() + "\n\n" + entry
open(path, "w").write(text)
PY
    ok "CHANGELOG.md updated"
}

do_commit() {
    git add appcast.xml packaging/homebrew/marmot.rb CHANGELOG.md
    if ! git diff --cached --quiet; then
        git commit -q -m "Release $NEW: appcast, cask, changelog"
    fi
    ok "Committed (not pushed yet)"
}

do_tag() {
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git tag "$TAG"
    git push -q origin "$TAG"
    ok "Tag pushed"
}

do_github_release() {
    if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        if ! gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' | grep -qxF "$ZIP"; then
            gh release upload "$TAG" "$ZIP" --repo "$REPO" >/dev/null
        fi
    else
        gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Marmot $NEW" \
            --notes-file "$FINAL" >/dev/null
    fi
    ok "https://github.com/$REPO/releases/tag/$TAG"
}

do_verify_download() {
    local url dl sha i
    url="https://github.com/$REPO/releases/download/$TAG/$ZIP"
    sha=$(shasum -a 256 "$ZIP" | awk '{print $1}')
    dl=$(mktemp)
    for i in 1 2 3 4 5 6; do
        curl -fsSL -o "$dl" "$url" 2>/dev/null && break
        sleep 5
    done
    [ "$(shasum -a 256 "$dl" | awk '{print $1}')" = "$sha" ] \
        || die "The downloadable zip doesn't match the one built here."
    rm -f "$dl"
    ok "The release download matches the zip built here"
}

do_push_main() {
    git push -q origin main
    ok "Pushed: users are now being offered $NEW"
}

do_tap() {
    git -C "$TAP_DIR" pull -q --ff-only
    cp packaging/homebrew/marmot.rb "$TAP_DIR/Casks/marmot.rb"
    git -C "$TAP_DIR" add Casks/marmot.rb
    if ! git -C "$TAP_DIR" diff --cached --quiet; then
        git -C "$TAP_DIR" commit -q -m "Marmot $NEW"
    fi
    git -C "$TAP_DIR" push -q
    ok "Tap pushed"
}

run_step bump            "Bump the version to $NEW"
run_step build           "Build $ZIP"
run_step appcast         "Sign the update and add it to the feed (your Mac may ask for your Keychain password)"
run_step cask            "Update the Homebrew cask"
run_step changelog       "Add $NEW to CHANGELOG.md"
run_step commit          "Commit the feed, cask and changelog"
run_step tag             "Tag $TAG"
run_step github_release  "Publish the GitHub release with the zip"
run_step verify_download "Check the download"
run_step push_main       "Push main (users start getting the update now)"
run_step tap             "Update the Homebrew tap"

# ---------------------------------------------------------------- final checks
STEP="final checks"
say "Final checks (GitHub can take a few minutes to serve new files)"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
if eventually "$FEED" "<sparkle:shortVersionString>$NEW</sparkle:shortVersionString>"; then
    ok "Update feed lists $NEW"
else
    warn "The update feed doesn't show $NEW yet. Check $FEED in a few minutes."
fi
if eventually "$OLD_FEED" "<sparkle:shortVersionString>$NEW</sparkle:shortVersionString>"; then
    ok "The old EPeiffer94 feed address shows $NEW too (Marmot 4.0.0 and older use it)"
else
    warn "The old EPeiffer94 feed address doesn't show $NEW. If someone took that username, older installs can't update."
fi
if eventually "$TAP_RAW" "$SHA"; then
    ok "Homebrew cask matches the zip"
else
    warn "The Homebrew cask doesn't match the zip yet. Check $TAP_RAW in a few minutes."
fi

# The zip is safely on GitHub (checked above); don't let them pile up here.
rm -f "$ZIP" "$DRAFT" "$NOTES" "$FINAL" "$NOTES_FOR" "$STATE" .build/notes-commits.tsv .build/notes-prs.json
trap - ERR
say "Marmot $NEW is released"
echo "  https://github.com/$REPO/releases/tag/$TAG"
