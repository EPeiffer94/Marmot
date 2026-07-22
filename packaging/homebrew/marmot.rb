# Homebrew cask for Marmot.
# Lives in the tap repo: github.com/EPeiffer94/homebrew-marmot (Casks/marmot.rb)
# Regenerate for each release with: sh scripts/make-cask.sh
cask "marmot" do
  version "3.2.0"
  sha256 "16a6c0e9f4a146e2f7452194513c276b59cba463e80ebf08a845da61dd23d2c4"

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
