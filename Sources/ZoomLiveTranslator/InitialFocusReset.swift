import AppKit
import SwiftUI

struct InitialFocusReset: NSViewRepresentable {
    var settingsPresented = false

    func makeNSView(context: Context) -> FocusResetView { FocusResetView() }

    func updateNSView(_ view: FocusResetView, context: Context) {
        if view.settingsPresented != settingsPresented {
            view.settingsPresented = settingsPresented
            if !settingsPresented { view.clearInitialFocus() }
        }
    }

    final class FocusResetView: NSView {
        var settingsPresented = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearInitialFocus()
        }

        func clearInitialFocus() {
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window, self?.window === window else { return }
                window.makeFirstResponder(nil)
            }
        }
    }
}
