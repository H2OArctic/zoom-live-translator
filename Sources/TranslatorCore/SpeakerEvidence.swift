import Foundation

public struct SpeakerEvidence: Sendable {
    private var samples: [(Date, String?)] = []

    public init() {}

    public mutating func observe(_ name: String?, at date: Date = Date()) {
        samples.append((date, name))
        samples.removeAll { date.timeIntervalSince($0.0) > 120 }
    }

    public func speaker(from start: Date, through end: Date) -> String? {
        let relevant = samples.filter { $0.0 >= start.addingTimeInterval(-0.8) && $0.0 <= end }
        guard relevant.count >= 2, let first = relevant.first, let last = relevant.last,
              first.0 <= start.addingTimeInterval(0.8), end.timeIntervalSince(last.0) <= 1.5,
              let name = first.1, relevant.allSatisfy({ $0.1 == name }) else { return nil }
        for index in 1..<relevant.count where relevant[index].0.timeIntervalSince(relevant[index - 1].0) > 1.5 { return nil }
        return name
    }
}

public struct SpeakerFrame: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

public enum SpeakerFrameDetector {
    public static func frames(rgba: [UInt8], width: Int, height: Int) -> [SpeakerFrame] {
        guard width >= 90, height >= 60, width <= 1920, height <= 1200,
              rgba.count == width * height * 4 else { return [] }
        var mask = [UInt8](repeating: 0, count: width * height)
        for index in mask.indices {
            let offset = index * 4
            let r = Int(rgba[offset]), g = Int(rgba[offset + 1]), b = Int(rgba[offset + 2])
            if g > 90 && g > r * 13 / 10 && g > b * 12 / 10 { mask[index] = 1 }
        }
        var result: [SpeakerFrame] = []
        for seed in mask.indices where mask[seed] == 1 {
            var queue = [seed]
            mask[seed] = 2
            var cursor = 0
            var left = width, top = height, right = 0, bottom = 0
            while cursor < queue.count {
                let point = queue[cursor]
                cursor += 1
                let x = point % width, y = point / width
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let next = ny * width + nx
                        if mask[next] == 1 { mask[next] = 2; queue.append(next) }
                    }
                }
            }
            guard right - left >= 90, bottom - top >= 60,
                  queue.count < (right - left + 1) * (bottom - top + 1) / 4 else { continue }
            func green(_ x: Int, _ y: Int) -> Bool { mask[y * width + x] != 0 }
            let horizontal = (left...right).filter { x in
                (top...min(top + 3, bottom)).contains { green(x, $0) } &&
                (max(top, bottom - 3)...bottom).contains { green(x, $0) }
            }.count
            let vertical = (top...bottom).filter { y in
                (left...min(left + 3, right)).contains { green($0, y) } &&
                (max(left, right - 3)...right).contains { green($0, y) }
            }.count
            guard Double(horizontal) / Double(right - left + 1) > 0.85,
                  Double(vertical) / Double(bottom - top + 1) > 0.85 else { continue }
            result.append(SpeakerFrame(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
        }
        return result
    }
}
