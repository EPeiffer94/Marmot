# Homebrew cask for Marmot.
# Lives in the tap repo: github.com/EPeiffer94/homebrew-marmot (Casks/marmot.rb)
# Regenerate for each release with: sh scripts/make-cask.sh
cask "marmot" do
  version "3.0.3"
  sha256 "d4e76520bdcd33544dc7cd0bb05ae342893e14541280504931120e51a8607601"

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
