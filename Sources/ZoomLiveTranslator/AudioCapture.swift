import AVFoundation
import CoreMedia
import ScreenCaptureKit

actor MicrophoneCapture {
    private var session: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?
    private var receiver: MicrophoneReceiver?
    private var errorObserver: (any NSObjectProtocol)?

    func start(device: AudioDeviceID, ingress: AudioIngress,
               onError: @escaping @Sendable (String) -> Void) throws {
        stop()
        guard let uid = AudioDevices.uniqueID(of: device),
              let captureDevice = AVCaptureDevice(uniqueID: uid), captureDevice.hasMediaType(.audio) else {
            throw AppError("Выбранный микрофон недоступен. Обнови устройства и выбери его заново.")
        }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: captureDevice)
        let output = AVCaptureAudioDataOutput()
        let receiver = MicrophoneReceiver(ingress: ingress, onError: onError)
        output.setSampleBufferDelegate(receiver, queue: DispatchQueue(label: "translator.microphone.audio"))
        do {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            guard session.canAddInput(input) else {
                throw AppError("Не удалось настроить захват выбранного микрофона.")
            }
            session.addInput(input)
            guard session.canAddOutput(output) else {
                throw AppError("Не удалось настроить передачу аудио микрофона на распознавание.")
            }
            session.addOutput(output)
        }
        self.session = session
        self.output = output
        self.receiver = receiver
        errorObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                                              object: session, queue: nil) { notification in
            let description = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
            onError(description ?? "Ошибка захвата микрофона.")
        }
        session.startRunning()
        guard session.isRunning else { stop(); throw AppError("Не удалось запустить микрофон.") }
    }

    func stop() {
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
        errorObserver = nil
        session?.stopRunning()
        output?.setSampleBufferDelegate(nil, queue: nil)
        session = nil
        output = nil
        receiver = nil
    }
}

final class MicrophoneReceiver: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let ingress: AudioIngress
    private let onError: @Sendable (String) -> Void

    init(ingress: AudioIngress, onError: @escaping @Sendable (String) -> Void) {
        self.ingress = ingress
        self.onError = onError
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        AudioSampleBuffers.append(sampleBuffer, to: ingress, onError: onError)
    }
}

enum AudioSampleBuffers {
    static func append(_ sampleBuffer: CMSampleBuffer, to ingress: AudioIngress, onError: (String) -> Void) {
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0,
              let description = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)) else {
            onError("Не удалось прочитать формат входящего аудио.")
            return
        }
        buffer.frameLength = buffer.frameCapacity
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(buffer.frameLength), into: buffer.mutableAudioBufferList)
        guard status == noErr else { onError("Ошибка чтения аудиобуфера: \(status)."); return }
        ingress.append(buffer, presentationSeconds: sampleBuffer.presentationTimeStamp.seconds)
    }
}

final class StreamReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let ingress: AudioIngress
    private let onError: @Sendable (String) -> Void

    init(ingress: AudioIngress, onError: @escaping @Sendable (String) -> Void) {
        self.ingress = ingress
        self.onError = onError
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        AudioSampleBuffers.append(sampleBuffer, to: ingress, onError: onError)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) { onError(error.localizedDescription) }
}

@MainActor
final class MeetingCapture {
    private var stream: SCStream?
    private var receiver: StreamReceiver?

    func start(application: SCRunningApplication, display: SCDisplay, ingress: AudioIngress,
               onError: @escaping @MainActor (String) -> Void) async throws {
        let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let receiver = StreamReceiver(ingress: ingress) { message in Task { @MainActor in onError(message) } }
        let stream = SCStream(filter: filter, configuration: config, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .audio, sampleHandlerQueue: DispatchQueue(label: "translator.meeting.audio"))
        self.receiver = receiver
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() async {
        let previous = stream
        stream = nil
        try? await previous?.stopCapture()
        receiver = nil
    }
}
