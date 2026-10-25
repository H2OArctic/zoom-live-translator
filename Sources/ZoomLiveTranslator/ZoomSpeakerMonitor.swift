import Foundation
import ScreenCaptureKit
import TranslatorCore

actor ZoomSpeakerReader {
    func read(windowID: CGWindowID, processID: Int32) async throws -> String? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: {
            $0.windowID == windowID && $0.owningApplication?.processID == processID &&
            $0.owningApplication?.bundleIdentifier == "us.zoom.xos"
        }) else { throw AppError("Выбранное окно Zoom недоступно. Открой его и обнови список окон.") }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = min(1, 1280 / max(window.frame.width, 1), 900 / max(window.frame.height, 1))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return try ZoomSpeakerImageReader.speaker(in: image)
    }
}

@MainActor
final class ZoomSpeakerMonitor {
    private var task: Task<Void, Never>?

    func start(windowID: CGWindowID, processID: Int32, onSample: @escaping (String?, String?) -> Void) {
        stop()
        let reader = ZoomSpeakerReader()
        task = Task {
            while !Task.isCancelled {
                let name: String?
                let failure: String?
                do { name = try await reader.read(windowID: windowID, processID: processID); failure = nil }
                catch { name = nil; failure = error.localizedDescription }
                guard !Task.isCancelled else { return }
                onSample(name, failure)
                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            }
        }
    }

    func stop() { task?.cancel(); task = nil }
}
