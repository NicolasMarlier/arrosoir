import AVFoundation
import Speech

/// Dictée vocale en français, transcrite sur l'iPhone pendant qu'on parle.
@Observable
final class Dictation {
    enum State: Equatable { case idle, recording, denied, unavailable }

    var state: State = .idle
    /// Texte reconnu pendant l'enregistrement en cours.
    var partial = ""
    var level: Float = 0

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private var onFinish: ((String) -> Void)?

    var isRecording: Bool { state == .recording }

    func start(onFinish: @escaping (String) -> Void) async {
        guard state != .recording else { return }
        guard await Self.authorize() else { state = .denied; return }
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }

        self.onFinish = onFinish
        partial = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(req, owner: self))
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: req, resultHandler: Self.makeHandler(owner: self))
            state = .recording
        } catch {
            cleanup()
            state = .unavailable
        }
    }

    func stop() {
        guard state == .recording else { return }
        let text = partial
        cleanup()
        state = .idle
        let cb = onFinish
        onFinish = nil
        cb?(text)
    }

    private func cleanup() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    fileprivate func update(text: String?, final: Bool) {
        if let text { partial = text }
        if final, state == .recording { stop() }
    }

    fileprivate func update(level: Float) { self.level = level }

    // Les closures audio / reconnaissance tournent hors du thread principal : on les crée hors MainActor.
    nonisolated private static func makeTap(_ req: SFSpeechAudioBufferRecognitionRequest, owner: Dictation) -> AVAudioNodeTapBlock {
        { buffer, _ in
            req.append(buffer)
            guard let data = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in stride(from: 0, to: n, by: 8) { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(1, n / 8)))
            let level = min(1, rms * 12)
            Task { @MainActor in owner.update(level: level) }
        }
    }

    nonisolated private static func makeHandler(owner: Dictation) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let final = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in owner.update(text: text, final: final) }
        }
    }

    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
