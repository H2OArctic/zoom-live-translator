import Testing
@testable import TranslatorCore

private func source(_ bundle: String, _ name: String, user: Bool = true, pid: Int32 = 1) -> ApplicationSource {
    ApplicationSource(processID: pid, bundleID: bundle, name: name, isUserApplication: user)
}

@Test func filtersHelpersSystemUIAndDuplicateInstances() {
    let result = ApplicationSourcePolicy.visible([
        source("com.google.Chrome", "Google Chrome", pid: 10),
        source("com.apple.finder", "Finder"), source("com.apple.Siri", "Siri"),
        source("com.example.autofill", "AutoFill", user: false),
        source("com.google.Chrome", "Google Chrome", pid: 11),
        source("local.zoom-live-translator", "Translator"), source("", "Service"),
        source("com.example.player", "Player")
    ])
    #expect(result.map(\.bundleID) == ["com.google.Chrome", "com.example.player"])
}

@Test func autoPrefersZoomThenBrowserButNeverAnUnrelatedApp() {
    let chrome = source("com.google.Chrome", "Chrome")
    let zoom = source("us.zoom.xos", "Zoom")
    let player = source("com.example.player", "Player")
    #expect(ApplicationSourcePolicy.resolve("automatic", in: [chrome, zoom]) == zoom)
    #expect(ApplicationSourcePolicy.resolve("automatic", in: [player, chrome]) == chrome)
    #expect(ApplicationSourcePolicy.resolve("automatic", in: [player]) == nil)
}

@Test func manualChoiceSurvivesOtherAppsStartingAndResolvesNewProcess() {
    let zoom = source("us.zoom.xos", "Zoom")
    let chrome = source("com.google.Chrome", "Chrome", pid: 22)
    #expect(ApplicationSourcePolicy.resolve(chrome.bundleID, in: [zoom, chrome]) == chrome)
    #expect(ApplicationSourcePolicy.resolve(chrome.bundleID, in: [zoom]) == nil)
    let restarted = source(chrome.bundleID, chrome.name, pid: 42)
    #expect(ApplicationSourcePolicy.resolve(chrome.bundleID, in: [zoom, restarted])?.processID == 42)
}
