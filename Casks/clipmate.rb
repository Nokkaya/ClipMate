cask "clipmate" do
  version "0.1.1"
  sha256 "9bf292826c9dc0bc75a5534f70caa676e85cec7649ae11b1cf2d23e6ae43fd4b"

  url "https://github.com/Nokkaya/ClipMate/releases/download/v#{version}/ClipMate-#{version}.dmg"
  name "ClipMate"
  desc "Native, privacy-first macOS clipboard history manager with AI integration"
  homepage "https://github.com/Nokkaya/ClipMate"

  livecheck do
    url "https://raw.githubusercontent.com/Nokkaya/ClipMate/main/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "ClipMate.app"

  uninstall quit: "com.clipmate.app"

  zap trash: [
    "~/Library/Application Support/ClipMate",
    "~/Library/Caches/com.clipmate.app",
    "~/Library/Preferences/com.clipmate.app.plist",
  ]
end
