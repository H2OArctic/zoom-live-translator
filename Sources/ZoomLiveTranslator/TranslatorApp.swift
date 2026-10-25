import SwiftUI

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(TranslatorAppDelegate.self) private var delegate
    @State private var model = TranslatorModel()

    var body: some Scene {
        WindowGroup("Zoom Live Translator") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 740)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1140, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class TranslatorAppDelegate: NSObject, NSApplicationDelegate {
    var model: TranslatorModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: icon)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
