import Foundation

/// Block B, half three: get events off this machine and onto `ambient-events`.
///
/// WHY THIS IS AN HTTP POST AND NOT A LASER SDK CALL
/// The Laser SDK ships for Rust, Python and TypeScript. There is no Swift SDK.
/// Rather than burn the afternoon on an Iggy TCP client in Swift, capture posts
/// newline-delimited JSON to `laser-bridge` on loopback, and the bridge (Python,
/// 200 lines, in this repo) publishes with the real SDK. Swap the bridge for a
/// native client after the hackathon and nothing above this file changes.
///
/// Two properties the demo depends on:
///   • Never blocks the capture loop. Events queue and flush on a background
///     queue; a slow bridge cannot stall window tracking.
///   • Never loses an event. Everything is appended to a local JSONL spool
///     BEFORE the POST is attempted. If the bridge is down, the spool is the
///     record and `laser-bridge replay` catches the stream up afterwards.
///     A dead network must not cost us the demo.
public final class EventPublisher {
    public struct Configuration {
        public var endpoint: URL
        public var spoolURL: URL
        public var flushInterval: TimeInterval
        public var maxBatch: Int

        public init(
            endpoint: URL = URL(string: "http://127.0.0.1:8077/events")!,
            spoolURL: URL = EventPublisher.defaultSpoolURL(),
            flushInterval: TimeInterval = 0.35,
            maxBatch: Int = 64
        ) {
            self.endpoint = endpoint
            self.spoolURL = spoolURL
            self.flushInterval = flushInterval
            self.maxBatch = maxBatch
        }
    }

    public static func defaultSpoolURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Onari", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ambient-events.jsonl")
    }

    private let config: Configuration
    private let queue = DispatchQueue(label: "ai.onari.ambient.publisher")
    private let session: URLSession
    private var buffer: [String] = []
    private var timer: DispatchSourceTimer?

    /// Observed so the menu bar can show green/amber without the UI reaching
    /// into the transport. Read on the main queue.
    public private(set) var lastPublishSucceeded = true
    public private(set) var publishedCount = 0
    public var onStatusChange: ((Bool, Int) -> Void)?

    public init(config: Configuration = Configuration()) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 2.0
        sessionConfig.waitsForConnectivity = false
        self.session = URLSession(configuration: sessionConfig)
        startTimer()
    }

    deinit { timer?.cancel() }

    // MARK: - Public API

    public func publish(_ event: AmbientEvent) {
        guard let line = try? event.encodedString() else {
            FileHandle.standardError.write(Data("publisher: could not encode event\n".utf8))
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.appendToSpool(line)
            self.buffer.append(line)
            if self.buffer.count >= self.config.maxBatch {
                self.flushLocked()
            }
        }
    }

    /// Flush and wait. Called on quit so the last note of the demo is not
    /// stranded in the buffer.
    public func drain(timeout: TimeInterval = 2.0) {
        let semaphore = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            self?.flushLocked()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
    }

    // MARK: - Internals

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + config.flushInterval, repeating: config.flushInterval)
        t.setEventHandler { [weak self] in self?.flushLocked() }
        t.resume()
        timer = t
    }

    /// Append-then-send. The spool write is synchronous and cheap; it is the
    /// durability guarantee, so it must not be skipped on the fast path.
    private func appendToSpool(_ line: String) {
        let data = Data((line + "\n").utf8)
        let path = config.spoolURL.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: config.spoolURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Must be called on `queue`.
    private func flushLocked() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(batch.joined(separator: "\n").utf8)

        let task = session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            let http = response as? HTTPURLResponse
            let ok = error == nil && (200..<300).contains(http?.statusCode ?? 0)
            self.queue.async {
                self.lastPublishSucceeded = ok
                if ok { self.publishedCount += batch.count }
                let succeeded = self.lastPublishSucceeded
                let count = self.publishedCount
                DispatchQueue.main.async { self.onStatusChange?(succeeded, count) }
            }
            if !ok {
                let reason = error?.localizedDescription ?? "HTTP \(http?.statusCode ?? -1)"
                FileHandle.standardError.write(
                    Data("publisher: bridge unreachable (\(reason)); \(batch.count) event(s) held in the spool\n".utf8)
                )
            }
        }
        task.resume()
    }
}
