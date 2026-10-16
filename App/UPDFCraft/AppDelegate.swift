import AppKit
import CraftKit

/// Ilovaga kirish nuqtasi. Storyboard/XIB yo'q: menyu kodda quriladi,
/// hujjatlarni `NSDocumentController` boshqaradi (Info.plist → `CraftDocument`).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.mainMenu = MainMenu.make()
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
    }

    /// M0 — faqat ko'ruvchi: bo'sh hujjat yaratilmaydi.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Engine: \(EngineActor.version)"),
        ])
    }
}
