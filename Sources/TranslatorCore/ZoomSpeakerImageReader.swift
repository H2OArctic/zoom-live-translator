import Foundation
import CoreGraphics
import Vision

public enum ZoomSpeakerImageReader {
    public static func speaker(in image: CGImage) throws -> String? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        let frames = SpeakerFrameDetector.frames(rgba: pixels, width: width, height: height)
        guard frames.count == 1, let frame = frames.first else { return nil }
        let band = min(50, frame.height / 3)
        guard let crop = image.cropping(to: CGRect(x: frame.x + 4, y: frame.y + frame.height - band,
                                                  width: frame.width - 8, height: band - 3)) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "ru-RU"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: crop).perform([request])
        let candidates = (request.results ?? []).compactMap { observation -> (String, Float)? in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.75,
                  observation.boundingBox.midX < 0.7 else { return nil }
            let name = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...80).contains(name.count), name.contains(where: \.isLetter) else { return nil }
            return (name, candidate.confidence)
        }
        guard candidates.count == 1 else { return nil }
        return candidates.first?.0
    }
}
