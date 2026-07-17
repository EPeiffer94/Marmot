#!/bin/sh
# Regenerates packaging/homebrew/marmot.rb for the current release zip.
# Run after `make release`, then copy the file into the tap repo:
#   github.com/EPeiffer94/homebrew-marmot → Casks/marmot.rb
set -e
cd "$(dirname "$0")/.."

VERSION=$(grep '^VERSION' Makefile | head -1 | sed 's/.*= *//')
ZIP="Marmot-$VERSION.zip"
[ -f "$ZIP" ] || { echo "Missing $ZIP — run 'make release' first."; exit 1; }
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

cat > packaging/homebrew/marmot.rb << EOF
# Homebrew cask for Marmot.
# Lives in the tap repo: github.com/EPeiffer94/homebrew-marmot (Casks/marmot.rb)
# Regenerate for each release with: sh scripts/make-cask.sh
cask "marmot" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/EPeiffer94/Marmot/releases/download/v#{version}/Marmot-#{version}.zip"
  name "Marmot"
  desc "Free, open-source Mac cleaner that shows everything before it touches anything"
  homepage "https://github.com/EPeiffer94/Marmot"

  # Marmot updates itself via Sparkle after install.
  auto_updates true
  depends_on macos: :ventura

  app "Marmot.app"

  zap trash: [
    "~/Library/Application Support/Marmot",
    "~/Library/Preferences/dev.marmot.app.plist",
  ]

  caveats <<~CAVEATS
    Marmot is not notarized (free community software). On first launch:
    System Settings → Privacy & Security → "Open Anyway".
    Or clear quarantine directly:
      xattr -cr /Applications/Marmot.app
  CAVEATS
end
EOF

echo "packaging/homebrew/marmot.rb updated for $VERSION ($SHA)"
echo "Copy it to the homebrew-marmot repo as Casks/marmot.rb and push."
