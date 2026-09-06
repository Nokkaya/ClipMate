import AppKit
import ClipMateCore

// ClipMate 入口：菜单栏常驻（accessory 策略，无 Dock 图标）。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
