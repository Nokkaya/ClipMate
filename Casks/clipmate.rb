cask "clipmate" do
  version "0.2.0"
  sha256 :no_check # 正式发版时填入具体校验和

  url "https://github.com/zhangdi/ClipMate/releases/download/v#{version}/ClipMate-#{version}.dmg"
  name "ClipMate"
  desc "Native, privacy-first macOS clipboard history manager with AI integration"
  homepage "https://github.com/zhangdi/ClipMate"

  livecheck do
    url "https://raw.githubusercontent.com/zhangdi/ClipMate/main/appcast.xml"
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
