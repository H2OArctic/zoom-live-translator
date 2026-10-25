import Foundation
import Testing
@testable import TranslatorCore

@Test func speakerIsRetainedOnlyAcrossContinuousMatchingObservations() {
    let start = Date(timeIntervalSince1970: 100)
    var evidence = SpeakerEvidence()
    evidence.observe("Alice", at: start.addingTimeInterval(-0.4))
    evidence.observe("Alice", at: start.addingTimeInterval(0.3))
    evidence.observe("Alice", at: start.addingTimeInterval(0.9))
    #expect(evidence.speaker(from: start, through: start.addingTimeInterval(1)) == "Alice")
    evidence.observe("Bob", at: start.addingTimeInterval(1.3))
    #expect(evidence.speaker(from: start, through: start.addingTimeInterval(1.4)) == nil)
    #expect(evidence.speaker(from: start, through: start.addingTimeInterval(4)) == nil)
}

@Test func missingOrStaleSpeakerDoesNotBecomeAnIdentity() {
    let start = Date(timeIntervalSince1970: 100)
    var evidence = SpeakerEvidence()
    #expect(evidence.speaker(from: start, through: start) == nil)
    evidence.observe("Alice", at: start)
    evidence.observe(nil, at: start.addingTimeInterval(0.6))
    #expect(evidence.speaker(from: start, through: start.addingTimeInterval(0.7)) == nil)
    var gap = SpeakerEvidence()
    gap.observe("Alice", at: start)
    gap.observe("Alice", at: start.addingTimeInterval(4))
    #expect(gap.speaker(from: start, through: start.addingTimeInterval(4)) == nil)
}

@Test func greenFrameDetectionRequiresClosedBordersAndRejectsFilledAreas() {
    let width = 360, height = 180
    func image(frames: [(Int, Int, Int, Int)], filled: Bool = false, open: Bool = false) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (left, top, right, bottom) in frames {
            for y in top...bottom {
                for x in left...right where filled || x == left || x == right || y == top || (!open && y == bottom) {
                    let offset = (y * width + x) * 4
                    bytes[offset] = 30; bytes[offset + 1] = 200
                    bytes[offset + 2] = 60; bytes[offset + 3] = 255
                }
            }
        }
        return bytes
    }
    let one = SpeakerFrameDetector.frames(rgba: image(frames: [(10, 10, 160, 150)]), width: width, height: height)
    #expect(one == [SpeakerFrame(x: 10, y: 10, width: 151, height: 141)])
    #expect(SpeakerFrameDetector.frames(rgba: image(frames: [(10, 10, 160, 150)], open: true), width: width, height: height).isEmpty)
    #expect(SpeakerFrameDetector.frames(rgba: image(frames: [(10, 10, 160, 150)], filled: true), width: width, height: height).isEmpty)
    #expect(SpeakerFrameDetector.frames(rgba: image(frames: [(10, 10, 160, 150), (190, 10, 340, 150)]), width: width, height: height).count == 2)
}
