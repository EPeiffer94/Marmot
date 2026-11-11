#!/bin/sh
# Signs a release zip with the Sparkle EdDSA key (from your Keychain) and
# inserts the corresponding <item> into appcast.xml.
#
# Usage: sh scripts/make-appcast-entry.sh                     (uses the Makefile VERSION)
#        sh scripts/make-appcast-entry.sh Marmot-2.1.0.zip 2.1.0
#        NOTES_FILE=notes.md sh scripts/make-appcast-entry.sh  (adds release notes,
#            shown in the in-app update window)
#
# The version and build number are read from the app INSIDE the zip, so the
# appcast always matches what users download — even if you re-run this after
# committing. (A mismatched build number makes Sparkle offer the same update
# forever.)
set -e
cd "$(dirname "$0")/.."

MAKE_VER=$(grep '^VERSION' Makefile | head -1 | sed 's/.*= *//')
ZIP="${1:-Marmot-$MAKE_VER.zip}"
[ -f "$ZIP" ] || { echo "Zip not found: $ZIP — run 'make release' first."; exit 1; }

PLIST=$(mktemp)
unzip -p "$ZIP" "Marmot.app/Contents/Info.plist" > "$PLIST" \
    || { rm -f "$PLIST"; echo "Could not read Marmot.app/Contents/Info.plist from $ZIP."; exit 1; }
BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
ZIP_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
rm -f "$PLIST"

VER="${2:-$ZIP_VER}"
[ "$VER" = "$ZIP_VER" ] || { echo "Version mismatch: you passed $VER but $ZIP contains $ZIP_VER."; exit 1; }

SIGN=$(find .build/artifacts -name sign_update -type f 2>/dev/null | head -1)
[ -n "$SIGN" ] || { echo "sign_update tool not found — run 'swift build -c release' first."; exit 1; }

SIG_ATTRS=$("$SIGN" "$ZIP")

NOTES_HTML=""
if [ -n "${NOTES_FILE:-}" ]; then
    [ -f "$NOTES_FILE" ] || { echo "Release notes not found: $NOTES_FILE"; exit 1; }
    NOTES_HTML=$(python3 scripts/notes_to_html.py "$NOTES_FILE")
fi

export ZIP VER SIG_ATTRS BUILD_NUM NOTES_HTML
python3 << 'EOF'
import os
import email.utils

zip_name = os.path.basename(os.environ["ZIP"])
ver = os.environ["VER"]
notes = os.environ.get("NOTES_HTML", "").strip()
# Sparkle shows <description> HTML as the release notes in the update window.
desc = f"\n      <description><![CDATA[\n{notes}\n      ]]></description>" if notes else ""
item = f"""    <item>
      <title>Marmot {ver}</title>{desc}
      <pubDate>{email.utils.formatdate(localtime=True)}</pubDate>
      <sparkle:version>{os.environ["BUILD_NUM"]}</sparkle:version>
      <sparkle:shortVersionString>{ver}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/Kasakir-AI/Marmot/releases/download/v{ver}/{zip_name}" {os.environ["SIG_ATTRS"].strip()} type="application/octet-stream" />
    </item>"""

path = "appcast.xml"
content = open(path).read()
marker = "<!-- MARMOT_APPCAST_ITEMS -->"
assert marker in content, "marker missing from appcast.xml"

# Replace any existing entry for this version — running the script twice must
# never stack duplicate items (mismatched signatures break Sparkle updates).
import re
pattern = re.compile(
    r"\n\s*<item>(?:(?!</item>).)*?<sparkle:shortVersionString>"
    + re.escape(ver)
    + r"</sparkle:shortVersionString>(?:(?!</item>).)*?</item>",
    re.DOTALL)
content, removed = pattern.subn("", content)
if removed:
    print(f"Replaced {removed} existing {ver} entr{'y' if removed == 1 else 'ies'}")

open(path, "w").write(content.replace(marker, marker + "\n" + item, 1))
print(f"appcast.xml updated for Marmot {ver} (build {os.environ['BUILD_NUM']})")
EOF

echo ""
echo "Next steps:"
echo "  1. git add appcast.xml && git commit -m 'Appcast: $VER' && git push"
echo "  2. Create the GitHub release v$VER and upload $ZIP as its asset"
echo "     (the asset name must stay exactly '$(basename "$ZIP")')."
