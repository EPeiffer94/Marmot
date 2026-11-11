#!/bin/bash
# Double-click in Finder to release Marmot. Opens Terminal and runs
# scripts/release.sh, which checks everything before changing anything.
cd "$(dirname "$0")/.." || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [ -f .build/release-state ]; then
    UNFINISHED=$(head -1 .build/release-state | sed 's/^version //')
    echo "Marmot $UNFINISHED was only partly released."
    read -r -p "Finish releasing it now? [Y/n]: " ANSWER
    case "$ANSWER" in
        n|N|no|No) echo "OK. Run this again when you're ready." ;;
        *) bash scripts/release.sh patch resume ;;
    esac
    echo ""
    read -r -p "Press Return to close this window."
    exit 0
fi
CURRENT=$(grep '^VERSION' Makefile | head -1 | sed 's/.*= *//')
echo "Marmot release — current version $CURRENT"
echo ""
echo "  patch  = bug fixes      (e.g. $CURRENT → next x.y.Z)"
echo "  minor  = new features   (next x.Y.0)"
echo "  major  = big changes    (next X.0.0)"
echo "  or type an exact version like 4.2.0"
echo ""
read -r -p "Release type [patch]: " KIND
bash scripts/release.sh "${KIND:-patch}"
echo ""
read -r -p "Press Return to close this window."
