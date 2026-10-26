cask "clipmate" do
  version "0.1.0"
  sha256 "c777ba24b0c106d14ab0517a12c223e8ca498bd4234c36293e67619183190cee"

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
