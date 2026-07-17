#!/bin/sh
# Signs a release zip with the Sparkle EdDSA key (from your Keychain) and
# inserts the corresponding <item> into appcast.xml.
#
# Usage: sh scripts/make-appcast-entry.sh Marmot-2.1.0.zip 2.1.0
set -e
cd "$(dirname "$0")/.."

ZIP="$1"
VER="$2"
[ -n "$ZIP" ] && [ -n "$VER" ] || { echo "Usage: sh scripts/make-appcast-entry.sh <zipfile> <version>"; exit 1; }
[ -f "$ZIP" ] || { echo "Zip not found: $ZIP — run 'make release' first."; exit 1; }

SIGN=$(find .build/artifacts -name sign_update -type f 2>/dev/null | head -1)
[ -n "$SIGN" ] || { echo "sign_update tool not found — run 'swift build -c release' first."; exit 1; }

SIG_ATTRS=$("$SIGN" "$ZIP")
BUILD_NUM=$(git rev-list --count HEAD)

export ZIP VER SIG_ATTRS BUILD_NUM
python3 << 'EOF'
import os
import email.utils

zip_name = os.path.basename(os.environ["ZIP"])
ver = os.environ["VER"]
item = f"""    <item>
      <title>Marmot {ver}</title>
      <pubDate>{email.utils.formatdate(localtime=True)}</pubDate>
      <sparkle:version>{os.environ["BUILD_NUM"]}</sparkle:version>
      <sparkle:shortVersionString>{ver}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/EPeiffer94/Marmot/releases/download/v{ver}/{zip_name}" {os.environ["SIG_ATTRS"].strip()} type="application/octet-stream" />
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
