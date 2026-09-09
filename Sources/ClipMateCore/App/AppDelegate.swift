import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let model = try AppModel()
            self.model = model
            model.start()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = L10n.tr("app.launch_failed")
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}
