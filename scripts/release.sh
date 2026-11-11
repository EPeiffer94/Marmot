#!/bin/bash
# One-command Marmot release: bump, build, sign, publish, and sync Homebrew.
#
#   make ship                 patch release   (4.1.0 -> 4.1.1)
#   make ship BUMP=minor      minor release   (4.1.0 -> 4.2.0)
#   make ship BUMP=major      major release   (4.1.0 -> 5.0.0)
#   make ship BUMP=4.3.0      exact version
#   make ship DRY=1           checks + release notes only, changes nothing
#
# Or double-click "scripts/Release Marmot.command" in Finder.
#
# Order matters and is enforced here: the tag and the GitHub release (with
# the zip) go up BEFORE main is pushed, because pushing main publishes the
# appcast — and users must never be offered an update with no download.
set -euo pipefail
cd "$(dirname "$0")/.."
# Finder/Terminal launches can miss Homebrew's folder (where gh lives).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

BUMP="${1:-patch}"
DRY="${2:-}"
REPO="Kasakir-AI/Marmot"
TAP_DIR="../homebrew-marmot"
EXPECTED_EMAIL="214017273+Kasakir-AI@users.noreply.github.com"
STEP="checks"
DONE=""

say()  { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
die()  {
    printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2
    # Past the checks, also say what state the release was left in.
    if [ "$STEP" != "checks" ]; then trap - ERR; on_error; fi
    exit 1
}

on_error() {
    printf '\n\033[31m✗ Release stopped during: %s\033[0m\n' "$STEP" >&2
    if [ -n "$DONE" ]; then
        printf 'Already done:%b\n' "$DONE" >&2
    else
        printf 'Nothing was changed.\n' >&2
    fi
    case "$STEP" in
        "checks"|"bump version"|"build zip"|"sign + appcast"|"cask"|"commit appcast + cask")
            printf 'Nothing is public yet. Users are not affected.\n' >&2 ;;
        "tag"|"GitHub release"|"verify download")
            printf 'Users are NOT offered the update yet (main has not been pushed).\n' >&2 ;;
        *)
            printf 'The app update is live. Only the Homebrew step may be unfinished.\n' >&2 ;;
    esac
    printf 'Paste this output to Claude to finish the release by hand.\n' >&2
}
trap on_error ERR

# ---------------------------------------------------------------- checks
say "Checking everything before changing anything"

[ "$(uname)" = "Darwin" ] || die "Run this on your Mac."
for tool in git gh swift make ditto shasum curl python3 unzip; do
    command -v "$tool" >/dev/null || die "Missing tool: $tool"
done
ok "Tools present"

gh auth status >/dev/null 2>&1 || die "GitHub CLI isn't signed in. Run: gh auth login"
LOGIN=$(gh api user --jq .login)
[ "$(echo "$LOGIN" | tr '[:upper:]' '[:lower:]')" = "kasakir-ai" ] \
    || die "GitHub CLI is signed in as $LOGIN, not Kasakir-AI."
ok "GitHub CLI signed in as $LOGIN"

EMAIL=$(git config user.email || true)
[ "$EMAIL" = "$EXPECTED_EMAIL" ] \
    || die "git commits would use \"$EMAIL\". Run: git config user.email $EXPECTED_EMAIL"
ok "Commits will use your GitHub no-reply email"

[ "$(git branch --show-current)" = "main" ] || die "Switch to main first: git switch main"
[ -z "$(git status --porcelain)" ] || die "Uncommitted changes. Commit or stash them first:
$(git status --short)"
git fetch -q origin --tags
LOCAL=$(git rev-parse main); REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" != "$REMOTE" ]; then
    if git merge-base --is-ancestor main origin/main; then
        git merge -q --ff-only origin/main
        ok "Pulled the latest main from GitHub"
    elif git merge-base --is-ancestor origin/main main; then
        die "Local main has commits that aren't on GitHub yet. Push them and let CI pass first: git push"
    else
        die "Local main and GitHub main have diverged. Sort that out first."
    fi
else
    ok "main is up to date with GitHub"
fi

CURRENT=$(grep '^VERSION' Makefile | head -1 | sed 's/.*= *//')
NEW=$(python3 - "$CURRENT" "$BUMP" <<'PY'
import re, sys
cur, bump = sys.argv[1], sys.argv[2]
parts = [int(p) for p in cur.split(".")]
if bump == "patch":   new = [parts[0], parts[1], parts[2] + 1]
elif bump == "minor": new = [parts[0], parts[1] + 1, 0]
elif bump == "major": new = [parts[0] + 1, 0, 0]
elif re.fullmatch(r"\d+\.\d+\.\d+", bump): new = [int(p) for p in bump.split(".")]
else: sys.exit(f"Not a version: {bump!r} (use patch, minor, major, or e.g. 4.2.0)")
if new <= parts: sys.exit(f"{'.'.join(map(str, new))} is not newer than {cur}")
print(".".join(map(str, new)))
PY
) || die "Bad version."
TAG="v$NEW"
ZIP="Marmot-$NEW.zip"
ok "Version $CURRENT → $NEW"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
    die "Tag $TAG already exists."
fi
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && die "GitHub release $TAG already exists."
ok "$TAG is unused"

HEAD_SHA=$(git rev-parse HEAD)
RUN_ID=$(gh run list --repo "$REPO" --workflow CI --commit "$HEAD_SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')
[ -n "$RUN_ID" ] || die "No CI run found for the current commit. Push main and let CI finish first."
CI_STATUS=$(gh run view "$RUN_ID" --repo "$REPO" --json status --jq .status)
if [ "$CI_STATUS" != "completed" ]; then
    echo "  CI is still running; waiting for it…"
    gh run watch "$RUN_ID" --repo "$REPO" --exit-status >/dev/null || die "CI failed on the current commit."
fi
[ "$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion --jq .conclusion)" = "success" ] \
    || die "CI didn't pass on the current commit: https://github.com/$REPO/actions/runs/$RUN_ID"
ok "CI passed on the commit being released"

[ -d "$TAP_DIR/.git" ] || die "Homebrew tap not found at $TAP_DIR"
[ -z "$(git -C "$TAP_DIR" status --porcelain)" ] || die "The Homebrew tap folder has uncommitted changes."
[ "$(git -C "$TAP_DIR" branch --show-current)" = "main" ] || die "The Homebrew tap folder isn't on main."
[ "$(git -C "$TAP_DIR" config user.email || true)" = "$EXPECTED_EMAIL" ] \
    || die "The Homebrew tap's commits would not use your no-reply email. Run: git -C $TAP_DIR config user.email $EXPECTED_EMAIL"
git -C "$TAP_DIR" pull -q --ff-only
ok "Homebrew tap is clean and up to date"

# ---------------------------------------------------------------- notes
mkdir -p .build
NOTES=".build/release-notes-$NEW.md"
if [ ! -s "$NOTES" ]; then
    PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
    {
        echo "<!-- Edit these notes; lines starting with <!-- are removed. Save and close. -->"
        git log --no-merges --format='- %s' ${PREV_TAG:+"$PREV_TAG"..HEAD} \
            | grep -v -E '^- (Release [0-9]|Bump version)' || true
    } > "$NOTES"
fi
say "Release notes: $NOTES"
open -e "$NOTES"
echo "  TextEdit opened the notes. Edit them, save, and close the window."

if [ "$DRY" = "dry" ]; then
    trap - ERR
    say "Dry run finished: every check passed. Nothing was changed."
    exit 0
fi

echo ""
read -r -p "  Type $NEW to release it (anything else cancels): " CONFIRM
[ "$CONFIRM" = "$NEW" ] || { trap - ERR; echo "Cancelled. Nothing was changed."; exit 0; }
grep -v '^<!--' "$NOTES" > "$NOTES.final"
[ -s "$NOTES.final" ] || die "The release notes are empty."

# ---------------------------------------------------------------- release
STEP="bump version"
say "Bumping VERSION to $NEW"
python3 - "$NEW" <<'PY'
import re, sys
s = open("Makefile").read()
s, n = re.subn(r"^VERSION = .*$", f"VERSION = {sys.argv[1]}", s, count=1, flags=re.M)
assert n == 1
open("Makefile", "w").write(s)
PY
git commit -q -am "Bump version to $NEW"
git push -q origin main   # safe: the appcast is unchanged, nobody is offered anything
DONE="$DONE\n  - Version bump committed and pushed"
ok "Committed and pushed"

STEP="build zip"
say "Building $ZIP"
make release > .build/release-build.log 2>&1 || die "The build failed. Details: .build/release-build.log"
BUILD=$(git rev-list --count HEAD)
PLIST=$(mktemp)
unzip -p "$ZIP" "Marmot.app/Contents/Info.plist" > "$PLIST"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" = "$NEW" ] || die "Zip has the wrong version."
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")" = "$BUILD" ] || die "Zip has the wrong build number."
rm -f "$PLIST"
DONE="$DONE\n  - Built $ZIP (build $BUILD)"
ok "Built $ZIP: version $NEW, build $BUILD"

STEP="sign + appcast"
say "Signing (your Mac may ask for your Keychain password)"
sh scripts/make-appcast-entry.sh >/dev/null
DONE="$DONE\n  - appcast.xml updated (not pushed)"
ok "appcast.xml updated"

STEP="cask"
sh scripts/make-cask.sh >/dev/null
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
ok "Cask updated (sha256 $SHA)"

STEP="commit appcast + cask"
git add appcast.xml packaging/homebrew/marmot.rb
git commit -q -m "Release $NEW: appcast + cask"
DONE="$DONE\n  - Appcast + cask committed locally (not pushed)"

STEP="tag"
say "Tagging $TAG"
git tag "$TAG"
git push -q origin "$TAG"
DONE="$DONE\n  - Tag $TAG pushed"
ok "Tag pushed"

STEP="GitHub release"
say "Publishing the GitHub release"
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Marmot $NEW" --notes-file "$NOTES.final" >/dev/null
DONE="$DONE\n  - GitHub release $TAG published with $ZIP"
ok "https://github.com/$REPO/releases/tag/$TAG"

STEP="verify download"
URL="https://github.com/$REPO/releases/download/$TAG/$ZIP"
DL=$(mktemp)
for i in 1 2 3 4 5 6; do
    curl -fsSL -o "$DL" "$URL" 2>/dev/null && break
    sleep 5
done
[ "$(shasum -a 256 "$DL" | awk '{print $1}')" = "$SHA" ] || die "The downloadable zip doesn't match the local one."
rm -f "$DL"
ok "Release download matches the local zip"

STEP="push main"
say "Pushing main (users start getting the update now)"
git push -q origin main
DONE="$DONE\n  - main pushed: the update is live"
ok "Pushed"

STEP="Homebrew tap"
say "Updating the Homebrew tap"
cp packaging/homebrew/marmot.rb "$TAP_DIR/Casks/marmot.rb"
git -C "$TAP_DIR" add Casks/marmot.rb
git -C "$TAP_DIR" commit -q -m "Marmot $NEW"
git -C "$TAP_DIR" push -q
DONE="$DONE\n  - Homebrew tap updated"
ok "Tap pushed"

STEP="final checks"
say "Final checks"
FEED_OK=""
for i in $(seq 1 12); do
    if curl -fsSL "https://raw.githubusercontent.com/$REPO/main/appcast.xml?nocache=$(date +%s)" \
        | grep -q "<sparkle:shortVersionString>$NEW</sparkle:shortVersionString>"; then
        FEED_OK=1; break
    fi
    sleep 10
done
[ -n "$FEED_OK" ] && ok "Update feed lists $NEW" \
    || echo "  ! GitHub hasn't served the new feed yet (it can lag a few minutes). Check later."
TAP_SHA=$(curl -fsSL "https://raw.githubusercontent.com/Kasakir-AI/homebrew-marmot/main/Casks/marmot.rb?nocache=$(date +%s)" \
    | sed -n 's/.*sha256 "\(.*\)".*/\1/p')
[ "$TAP_SHA" = "$SHA" ] && ok "Homebrew cask matches the zip" \
    || echo "  ! The tap hasn't caught up yet (it can lag a few minutes). Check later."

# The zip is safely on GitHub (checked above); don't let them pile up here.
rm -f "$NOTES" "$NOTES.final" "$ZIP"
trap - ERR
say "Marmot $NEW is released"
echo "  https://github.com/$REPO/releases/tag/$TAG"
