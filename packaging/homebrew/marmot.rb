# Homebrew cask for Marmot.
# Lives in the tap repo: github.com/Kasakir-AI/homebrew-marmot (Casks/marmot.rb)
# Regenerate for each release with: sh scripts/make-cask.sh
cask "marmot" do
  version "4.0.1"
  sha256 "789b6e78511b66ef09315ab096035b687ff542c7f53a1de0bf14155520c61019"

  url "https://github.com/Kasakir-AI/Marmot/releases/download/v#{version}/Marmot-#{version}.zip"
  name "Marmot"
  desc "Free, open-source Mac cleaner that shows everything before it touches anything"
  homepage "https://github.com/Kasakir-AI/Marmot"

  # Marmot updates itself via Sparkle after install.
  auto_updates true
  depends_on macos: :tahoe

  app "Marmot.app"

  zap trash: [
    "~/Library/Application Support/Marmot",
    "~/Library/Caches/dev.marmot.app",
    "~/Library/HTTPStorages/dev.marmot.app",
    "~/Library/Preferences/dev.marmot.app.plist",
    "~/Library/Saved Application State/dev.marmot.app.savedState",
  ]

  caveats <<~CAVEATS
    Marmot is not notarized (free community software). On first launch:
    System Settings → Privacy & Security → "Open Anyway".
    Or clear quarantine directly:
      xattr -cr /Applications/Marmot.app
  CAVEATS
end
