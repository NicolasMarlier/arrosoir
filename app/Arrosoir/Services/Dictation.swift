import AVFoundation
import Speech

/// Reçoit l'audio du micro (thread audio) et le transmet à la requête de reconnaissance en cours.
nonisolated final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ r: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); request = r; lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let r = request; lock.unlock()
        r?.append(buffer)
    }
}

/// Dictée continue en français, transcrite sur l'iPhone.
/// L'écoute ne s'arrête que quand on appelle `stop()` : après chaque pause, la reconnaissance repart toute seule.
@Observable
final class Dictation {
    enum State: Equatable { case idle, recording, denied, unavailable }

    var state: State = .idle
    /// Texte validé (phrases terminées).
    var committed = ""
    /// Texte en cours de reconnaissance.
    var partial = ""
    /// Niveau sonore 0…1 (0 pendant les silences).
    var level: Float = 0
    var startedAt = Date()

    var isRecording: Bool { state == .recording }
    var fullText: String { [committed, partial].filter { !$0.isEmpty }.joined(separator: " ") }

    private let engine = AVAudioEngine()
    private let sink = AudioSink()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var generation = 0
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))

    func start() async {
        guard state != .recording else { return }
        guard await Self.authorize() else { state = .denied; return }
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.makeTap(sink, owner: self))
            engine.prepare()
            try engine.start()
            committed = ""
            partial = ""
            startedAt = Date()
            state = .recording
            startTask()
        } catch {
            Telemetry.capture(error, feature: "dictation")
            teardown()
            state = .unavailable
        }
    }

    /// Arrête l'écoute et renvoie tout le texte reconnu.
    @discardableResult
    func stop() -> String {
        let text = fullText
        if state == .recording {
            teardown()
            state = .idle
        }
        committed = text
        partial = ""
        return text
    }

    private func startTask() {
        guard let recognizer else { return }
        generation += 1
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        sink.set(req)
        task = recognizer.recognitionTask(with: req, resultHandler: Self.makeHandler(owner: self, generation: generation))
    }

    private func commitPartial() {
        let p = partial.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { committed = committed.isEmpty ? p : committed + " " + p }
        partial = ""
    }

    fileprivate func handle(text: String?, final: Bool, failed: Bool, generation g: Int) {
        guard g == generation, state == .recording else { return }
        if let text { partial = text }
        if final || failed {
            commitPartial()
            request?.endAudio()
            task = nil
            // On relance aussitôt une nouvelle reconnaissance : l'écoute continue.
            if failed {
                Task { try? await Task.sleep(for: .milliseconds(300)); if self.state == .recording { self.startTask() } }
            } else {
                startTask()
            }
        }
    }

    fileprivate func setLevel(_ l: Float) {
        guard state == .recording else { return }
        level = l
    }

    private func teardown() {
        generation += 1
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        sink.set(nil)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Les closures audio / reconnaissance tournent hors du thread principal : on les crée hors MainActor.
    nonisolated private static func makeTap(_ sink: AudioSink, owner: Dictation) -> AVAudioNodeTapBlock {
        { buffer, _ in
            sink.append(buffer)
            guard let data = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            var count = 0
            for i in stride(from: 0, to: n, by: 4) { sum += data[i] * data[i]; count += 1 }
            let rms = sqrt(sum / Float(max(1, count)))
            // Échelle en décibels : une voix normale (≈ -35…-20 dB) remplit bien la barre,
            // le silence (< -50 dB) la laisse plate.
            let db = 20 * log10(max(rms, 1e-7))
            let norm = min(1, max(0, (db + 50) / 28))
            let level = norm < 0.12 ? 0 : sqrt(norm)
            Task { @MainActor in owner.setLevel(level) }
        }
    }

    nonisolated private static func makeHandler(owner: Dictation, generation: Int) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil && result == nil
            if failed, let error {
                let ns = error as NSError
                Telemetry.breadcrumb("Reconnaissance vocale interrompue", category: "dictation", data: ["domain": ns.domain, "code": ns.code], level: .warning)
            }
            Task { @MainActor in owner.handle(text: text, final: final, failed: failed, generation: generation) }
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
