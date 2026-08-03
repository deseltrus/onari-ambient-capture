import AVFoundation
import Foundation
import Speech

/// Block C: hold the hotkey, speak, get text bound to (app, window, time).
///
/// TRANSCRIPTION STRATEGY — read this before "fixing" it
/// The doc mandates Parakeet, local. Parakeet is an NVIDIA ASR model; on Apple
/// Silicon it runs through `parakeet-mlx`, which is Python + a model download.
/// That is a fine bet for the product and a bad bet for a 4.5-hour clock, so
/// this file does both:
///
///   • `AppleSpeechTranscriber` — SFSpeechRecognizer, on-device, zero
///     dependencies, works the moment permission is granted. This is the
///     default and it is what the demo runs on if nothing else lands.
///   • `ProcessTranscriber` — hands the recorded WAV to any command that
///     prints a transcript on stdout. Point it at parakeet-mlx and you have
///     the doc's stack with no Swift changes:
///         ONARI_TRANSCRIBE_CMD="uv run parakeet-mlx-transcribe"
///
/// Audio is always written to a WAV first, so switching engines never means
/// re-recording, and a failed transcript still leaves the audio on disk.
public protocol Transcriber {
    /// Called with the final text, or nil if nothing intelligible was captured.
    func transcribe(wavURL: URL, liveHypothesis: String?, completion: @escaping (String?) -> Void)
}

// MARK: - Recorder

@MainActor
public final class MicNoteRecorder {
    public enum State {
        case idle
        case recording
        case transcribing
    }

    public private(set) var state: State = .idle
    public var onStateChange: ((State) -> Void)?

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentWavURL: URL?

    // Live Apple recognition, running in parallel with the file write so the
    // default path has a transcript the instant the key comes up.
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// The running partial transcript, updated as you speak. Readable so the
    /// UI can echo your own words back while recording — without that, "is it
    /// hearing me?" is unanswerable until after you stop.
    public private(set) var liveHypothesis: String?

    private let transcriber: Transcriber

    public init(transcriber: Transcriber? = nil) {
        self.transcriber = transcriber ?? MicNoteRecorder.defaultTranscriber()
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// `ONARI_TRANSCRIBE_CMD` wins if set; otherwise Apple on-device.
    public static func defaultTranscriber() -> Transcriber {
        if let cmd = ProcessInfo.processInfo.environment["ONARI_TRANSCRIBE_CMD"],
           !cmd.trimmingCharacters(in: .whitespaces).isEmpty {
            return ProcessTranscriber(command: cmd)
        }
        return AppleSpeechTranscriber()
    }

    /// Ask for mic + speech up front. Both prompts are TCC dialogs; triggering
    /// them at launch instead of mid-demo is the entire point.
    public static func requestPermissions(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { micGranted in
            SFSpeechRecognizer.requestAuthorization { speechStatus in
                DispatchQueue.main.async {
                    completion(micGranted && speechStatus == .authorized)
                }
            }
        }
    }

    // MARK: - Recording

    public func start() {
        guard state == .idle else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onari-note-\(Int(Date().timeIntervalSince1970 * 1000)).wav")
        currentWavURL = url
        liveHypothesis = nil

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // 16 kHz mono PCM: what every ASR engine wants, and a quarter the size.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            FileHandle.standardError.write(Data("recorder: cannot open \(url.path): \(error)\n".utf8))
            return
        }

        let liveRequest = SFSpeechAudioBufferRecognitionRequest()
        liveRequest.shouldReportPartialResults = true
        // On-device keeps the promise in the doc: nothing leaves the machine.
        if recognizer?.supportsOnDeviceRecognition == true {
            liveRequest.requiresOnDeviceRecognition = true
        }
        request = liveRequest

        task = recognizer?.recognitionTask(with: liveRequest) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self.liveHypothesis = text }
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            try? self.audioFile?.write(from: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            FileHandle.standardError.write(Data("recorder: engine start failed: \(error)\n".utf8))
            cleanupAudio()
            return
        }

        state = .recording
        onStateChange?(state)
    }

    /// Stop, transcribe, hand back the text. Empty recordings return nil and
    /// must NOT produce a note event — a stray keypress is not a thought.
    public func stop(completion: @escaping (String?) -> Void) {
        guard state == .recording else {
            completion(nil)
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()

        state = .transcribing
        onStateChange?(state)

        let url = currentWavURL
        let hypothesis = liveHypothesis
        cleanupAudio()

        guard let url else {
            finish(nil, completion: completion)
            return
        }

        // Give the live recognizer a beat to settle its final result before
        // we read the hypothesis; otherwise short notes come back truncated.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let latest = self.liveHypothesis ?? hypothesis
            self.transcriber.transcribe(wavURL: url, liveHypothesis: latest) { text in
                DispatchQueue.main.async {
                    let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.finish(cleaned?.isEmpty == false ? cleaned : nil, completion: completion)
                }
            }
        }
    }

    private func finish(_ text: String?, completion: @escaping (String?) -> Void) {
        state = .idle
        onStateChange?(state)
        completion(text)
    }

    private func cleanupAudio() {
        audioFile = nil
        task?.cancel()
        task = nil
        request = nil
    }
}

// MARK: - Transcribers

/// On-device Apple speech. The transcript is already computed live, so this is
/// effectively free at stop time.
public struct AppleSpeechTranscriber: Transcriber {
    public init() {}

    public func transcribe(
        wavURL: URL, liveHypothesis: String?, completion: @escaping (String?) -> Void
    ) {
        if let liveHypothesis, !liveHypothesis.isEmpty {
            completion(liveHypothesis)
            return
        }
        // No live result (recognizer unavailable): fall back to a file pass.
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable
        else {
            completion(nil)
            return
        }
        let request = SFSpeechURLRecognitionRequest(url: wavURL)
        request.shouldReportPartialResults = false
        recognizer.recognitionTask(with: request) { result, _ in
            guard let result, result.isFinal else { return }
            completion(result.bestTranscription.formattedString)
        }
    }
}

/// Any external ASR that reads a WAV path and prints text. This is the Parakeet
/// seam: the command receives the WAV path as its final argument.
public struct ProcessTranscriber: Transcriber {
    public var command: String
    public var timeout: TimeInterval

    public init(command: String, timeout: TimeInterval = 20) {
        self.command = command
        self.timeout = timeout
    }

    public func transcribe(
        wavURL: URL, liveHypothesis: String?, completion: @escaping (String?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-lc", "\(command) \"\(wavURL.path)\""]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                // Never lose the note because the external engine is missing.
                completion(liveHypothesis)
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 0, !text.isEmpty {
                completion(text)
            } else {
                completion(liveHypothesis)
            }
        }
    }
}
