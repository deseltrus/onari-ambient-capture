import Foundation

@MainActor
final class ConsolidationViewModel: ObservableObject {
    @Published var response: ConsolidationResponse?
    @Published var draftMessage = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingAction: ConsolidationResponse.SuggestedAction?
    @Published var result: DispatchResult?

    /// Steps revealed one at a time so a rehearsed dispatch plays back as if it
    /// is executing live on stage.
    @Published var executionSteps: [ExecutionStep] = []
    @Published var isDispatching = false

    // Beautiful, non-instant loading: a line of what Onari is "thinking".
    @Published var loadingStage: String?

    // The suggested action is withheld until Onari has "thought it through"
    // after the session, then revealed with animation.
    @Published var isReasoningAction = false
    @Published var showAction = false

    // Voice input for the session chat (Parakeet / on-device Apple speech).
    @Published var isRecording = false
    @Published var liveTranscript = ""

    // Events live off the main surface; this drives the activity sheet.
    @Published var showTimeline = false

    let store: SessionStore
    private let service: Lane3Serving
    private let recorder = MicNoteRecorder()
    private var transcriptTimer: Timer?

    private static let loadingStages = [
        "Reviewing this session…",
        "Reconnecting to memory…",
        "Finding what you looked at but never wrote down…",
        "Assembling the picture…",
    ]

    init(store: SessionStore, service: Lane3Serving = Lane3Client()) {
        self.store = store
        self.service = service
        recorder.onStateChange = { [weak self] state in
            guard let self else { return }
            self.isRecording = (state == .recording)
        }
    }

    func consolidate() {
        guard !isLoading else { return }
        isLoading = true
        showAction = false
        isReasoningAction = false
        errorMessage = nil
        Task {
            for stage in Self.loadingStages {
                loadingStage = stage
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
            do {
                let response = try await service.consolidate(sessionId: store.session.id)
                self.response = response
                store.append(type: "guild.response", title: "New session insight", detail: response.summary)
                loadingStage = nil
                isLoading = false
                await revealActionAfterThinking()
            } catch {
                errorMessage = error.localizedDescription
                loadingStage = nil
                isLoading = false
            }
        }
    }

    /// The "thought out after the session" beat: a short reasoning pause, then
    /// the suggested action animates in.
    private func revealActionAfterThinking() async {
        guard response?.suggestedActions.isEmpty == false else { return }
        isReasoningAction = true
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        isReasoningAction = false
        showAction = true
    }

    func save() {
        guard let response else { return }
        store.save(response: response)
    }

    func ignore() {
        guard let response else { return }
        store.ignore(response: response)
        self.response = nil
        result = nil
        executionSteps = []
        showAction = false
    }

    // MARK: - Chat + voice

    func ask() {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        draftMessage = ""
        store.addChat(role: .user, text: text)
        isLoading = true
        Task {
            // A brief beat so replies never snap in instantly on stage.
            try? await Task.sleep(nanoseconds: 900_000_000)
            do {
                let reply = try await service.chat(
                    sessionId: store.session.id,
                    response: response,
                    message: text
                )
                store.addChat(role: .assistant, text: reply)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Toggle push-to-talk for the chat box.
    func toggleVoice() {
        if isRecording { stopVoice() } else { startVoice() }
    }

    private func startVoice() {
        liveTranscript = ""
        recorder.start()
        transcriptTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.liveTranscript = self.recorder.liveHypothesis ?? ""
                if !self.liveTranscript.isEmpty { self.draftMessage = self.liveTranscript }
            }
        }
    }

    private func stopVoice() {
        transcriptTimer?.invalidate()
        transcriptTimer = nil
        recorder.stop { [weak self] text in
            guard let self else { return }
            self.liveTranscript = ""
            if let text, !text.isEmpty {
                self.draftMessage = text
                self.ask()
            }
        }
    }

    // MARK: - Suggested action

    /// Hotkey / voice path: accept the suggested action and perform it now.
    func acceptSuggestedAction() {
        guard showAction, let action = response?.suggestedActions.first else { return }
        performAction(action)
    }

    func performAction(_ action: ConsolidationResponse.SuggestedAction) {
        guard let response, !isLoading else { return }
        pendingAction = nil
        isLoading = true
        isDispatching = true
        result = nil
        executionSteps = []
        store.append(type: "action.approved", title: action.label, detail: "Approved by user")
        Task {
            do {
                let result = try await service.dispatch(
                    sessionId: store.session.id,
                    response: response,
                    action: action
                )
                // Reveal the pipeline one step at a time — the "pretend live" beat.
                for step in result.steps ?? [] {
                    executionSteps.append(step)
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.result = result
                store.recordDispatch(result)
            } catch {
                errorMessage = error.localizedDescription
                store.append(type: "dispatch.failed", title: "Dispatch failed", detail: error.localizedDescription)
            }
            isDispatching = false
            isLoading = false
        }
    }

    /// Legacy confirmation-dialog path (kept for the non-WhatsApp scenario).
    func requestApproval(for action: ConsolidationResponse.SuggestedAction) {
        pendingAction = action
    }

    func cancelApproval() {
        pendingAction = nil
    }

    func approve() {
        guard let action = pendingAction else { return }
        performAction(action)
    }
}
