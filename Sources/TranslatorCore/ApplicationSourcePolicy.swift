import Foundation

public struct ApplicationSource: Sendable, Equatable {
    public let processID: Int32
    public let bundleID: String
    public let name: String
    public let isUserApplication: Bool

    public init(processID: Int32, bundleID: String, name: String, isUserApplication: Bool) {
        self.processID = processID
        self.bundleID = bundleID
        self.name = name
        self.isUserApplication = isUserApplication
    }
}

public enum ApplicationSourcePolicy {
    public static let automatic = "automatic"
    private static let preferred = ["us.zoom.xos", "com.google.Chrome", "com.apple.Safari",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "org.mozilla.firefox", "com.operasoftware.Opera"]
    private static let excluded: Set<String> = ["local.zoom-live-translator", "com.apple.finder", "com.apple.dock",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.systemuiserver",
        "com.apple.WindowManager", "com.apple.Siri", "com.apple.loginwindow", "com.apple.TextInputMenuAgent"]

    public static func visible(_ sources: [ApplicationSource]) -> [ApplicationSource] {
        var seen = Set<String>()
        return sources.filter {
            $0.isUserApplication && !$0.bundleID.isEmpty && !excluded.contains($0.bundleID) && seen.insert($0.bundleID).inserted
        }.sorted {
            let lhs = preferred.firstIndex(of: $0.bundleID) ?? preferred.count
            let rhs = preferred.firstIndex(of: $1.bundleID) ?? preferred.count
            return lhs == rhs ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lhs < rhs
        }
    }

    public static func resolve(_ selection: String, in sources: [ApplicationSource]) -> ApplicationSource? {
        let available = visible(sources)
        if selection != automatic { return available.first { $0.bundleID == selection } }
        return preferred.lazy.compactMap { bundle in available.first { $0.bundleID == bundle } }.first
    }
}
