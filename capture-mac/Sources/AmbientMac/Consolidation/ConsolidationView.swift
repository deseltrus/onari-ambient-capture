import SwiftUI

struct ConsolidationView: View {
    @ObservedObject var model: ConsolidationViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            thread
            Divider()
            inputBar
        }
        .frame(minWidth: 760, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.showTimeline) { timelineSheet }
        .alert(approvalTitle, isPresented: approvalPresented) {
            Button("Cancel", role: .cancel) { model.cancelApproval() }
            Button(approvalConfirm) { model.approve() }
        } message: {
            Text(approvalDetail)
        }
    }

    // MARK: - Header (top-left running indicator)

    private var header: some View {
        HStack(spacing: 14) {
            RunningIndicator(listening: model.isRecording)
            Spacer()
            Button { model.showTimeline = true } label: {
                Label("Activity", systemImage: "list.bullet.rectangle")
            }
            .help("Session events & timeline")
            Button { model.consolidate() } label: {
                Label("Rethink", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model.isLoading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - The conversation thread (main feed)

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let error = model.errorMessage {
                        errorBubble(error)
                    }

                    if model.response == nil && !model.isLoading {
                        emptyState
                    }

                    // Onari's opening move: the consolidated insight.
                    if let response = model.response {
                        onariBubble { insightWidget(response) }
                    }

                    // The back-and-forth.
                    ForEach(model.store.chat) { message in
                        chatBubble(message)
                    }

                    // Onari "thinking" — consolidating, replying, or reasoning.
                    if model.isLoading && model.response == nil {
                        onariBubble { thinkingWidget(model.loadingStage ?? "Thinking…") }
                    } else if model.isLoading && !model.isDispatching && model.response != nil {
                        onariBubble { typingWidget }
                    } else if model.isReasoningAction {
                        onariBubble { thinkingWidget("Deciding what would help…") }
                    }

                    // The suggested action, as a widget in the thread.
                    if model.showAction, let action = model.response?.suggestedActions.first {
                        onariBubble { actionWidget(action) }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                removal: .opacity))
                    }

                    // Execution pipeline widget.
                    if model.isDispatching || !model.executionSteps.isEmpty {
                        onariBubble { pipelineWidget }
                    }

                    // Result widget (the WhatsApp message).
                    if let result = model.result, let artifact = result.artifact {
                        onariBubble { resultWidget(result: result, artifact: artifact) }
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }

                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.showAction)
                .animation(.easeInOut(duration: 0.3), value: model.isReasoningAction)
                .animation(.easeInOut(duration: 0.3), value: model.executionSteps.count)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.result)
            }
            .onChange(of: model.store.chat.count) { scrollDown(proxy) }
            .onChange(of: model.executionSteps.count) { scrollDown(proxy) }
            .onChange(of: model.showAction) { scrollDown(proxy) }
            .onChange(of: model.isReasoningAction) { scrollDown(proxy) }
            .onChange(of: model.result) { scrollDown(proxy) }
            .onChange(of: model.loadingStage) { scrollDown(proxy) }
        }
    }

    private let bottomAnchor = "THREAD_BOTTOM"

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    // MARK: - Bubbles

    /// A left-aligned Onari message: avatar + content card.
    private func onariBubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            OnariAvatar()
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 36)
        }
    }

    private func chatBubble(_ message: ChatMessage) -> some View {
        Group {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 60)
                    Text(message.text)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15).padding(.vertical, 11)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                        .textSelection(.enabled)
                }
            } else {
                onariBubble {
                    Text(message.text)
                        .font(.system(size: 16))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func errorBubble(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 15))
            .foregroundStyle(.red)
            .padding(14)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "No session insight yet",
                systemImage: "sparkles",
                description: Text("Ask Onari to look back over this session and connect it to your memory.")
            )
            Button { model.consolidate() } label: {
                Text("Analyze this session").font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    // MARK: - Widgets (thread content)

    private func insightWidget(_ response: ConsolidationResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("WHAT I NOTICED")
                .font(.system(size: 12, weight: .bold)).tracking(1.1)
                .foregroundStyle(.purple)
            Text(response.summary)
                .font(.system(size: 23, weight: .semibold))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("WHY THIS SURFACED")
                .font(.system(size: 12, weight: .bold)).tracking(1.1)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(response.evidence) { evidence in
                    evidenceRow(evidence)
                }
            }

            HStack(spacing: 12) {
                Button("Save insight") { model.save() }
                Button("Ignore", role: .destructive) { model.ignore() }
                Spacer()
            }
            .controlSize(.regular)
        }
    }

    private func evidenceRow(_ evidence: ConsolidationResponse.Evidence) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: evidence.kind == "unspoken_board" ? "eye.fill"
                  : evidence.kind == "history_join" ? "clock.arrow.circlepath" : "note.text")
                .font(.system(size: 17))
                .foregroundStyle(evidence.kind == "unspoken_board" ? .purple
                                 : evidence.kind == "history_join" ? .blue : .teal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(evidence.label).font(.system(size: 16, weight: .semibold))
                    if evidence.kind == "unspoken_board" {
                        Text("UNSPOKEN")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.purple.opacity(0.16), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }
                Text(evidence.detail)
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func thinkingWidget(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .id(text)
                .transition(.opacity)
        }
    }

    private var typingWidget: some View {
        TypingDots()
    }

    private func actionWidget(_ action: ConsolidationResponse.SuggestedAction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                Text("Onari suggests").font(.system(size: 14, weight: .bold)).foregroundStyle(.purple)
                Spacer()
                Text("⌃⌥⌘↩ to send")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }
            Button { model.performAction(action) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paperplane.fill").font(.system(size: 17))
                    Text(action.label).font(.system(size: 17, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isLoading)
        }
    }

    private var pipelineWidget: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(.orange)
                Text(model.executionSteps.isEmpty ? "Sending to Hackathon 08/03 - TEAM O…" : "RocketRide execution pipeline")
                    .font(.system(size: 16, weight: .semibold))
                if model.isDispatching { ProgressView().controlSize(.small) }
            }
            if !model.executionSteps.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(model.executionSteps) { step in
                        stepRow(step)
                    }
                }
            }
        }
    }

    private func stepRow(_ step: ExecutionStep) -> some View {
        HStack(alignment: .top, spacing: 11) {
            stepIcon(for: step.status).font(.system(size: 16)).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.label).font(.system(size: 15, weight: .semibold))
                if let detail = step.detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func stepIcon(for status: String) -> some View {
        switch status {
        case "done": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case "skipped": Image(systemName: "minus.circle.fill").foregroundStyle(.gray)
        case "failed": Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        default: Image(systemName: "circle.dashed").foregroundStyle(.orange)
        }
    }

    private func resultWidget(result: DispatchResult, artifact: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: result.status == "failed" ? "xmark.circle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(result.status == "failed" ? .red : .green)
                Text(result.status == "failed" ? "Dispatch \(result.status)" : "Sent to Hackathon 08/03 - TEAM O")
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(artifact)
                .font(.system(size: 15))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.86, green: 0.97, blue: 0.86), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.black)
            if let trace = result.traceURL, let url = URL(string: trace) {
                Link(destination: url) {
                    Label("Open RocketRide execution trace", systemImage: "arrow.up.forward.square")
                        .font(.system(size: 13, weight: .medium))
                }
            }
        }
    }

    // MARK: - Input bar (with voice)

    private var inputBar: some View {
        Group {
            if model.isRecording {
                recordingBar
            } else {
                HStack(spacing: 12) {
                    Button { model.toggleVoice() } label: {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Speak to Onari")

                    TextField("Ask Onari about this session…", text: $model.draftMessage)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .onSubmit { model.ask() }

                    Button("Send") { model.ask() }
                        .controlSize(.large)
                        .disabled(model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(16)
    }

    /// Distinct recording state with an explicit Stop button. The pulse lives on
    /// a view that only exists while recording, so it never gets stuck running.
    private var recordingBar: some View {
        HStack(spacing: 14) {
            RecordingPulse()
            VStack(alignment: .leading, spacing: 2) {
                Text("Listening…").font(.system(size: 14, weight: .semibold)).foregroundStyle(.red)
                Text(model.liveTranscript.isEmpty ? "Speak your question" : model.liveTranscript)
                    .font(.system(size: 16))
                    .foregroundStyle(model.liveTranscript.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                model.toggleVoice()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Timeline sheet (events off the main surface)

    private var timelineSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Session activity").font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Done") { model.showTimeline = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.store.timeline.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.system(size: 15, weight: .semibold))
                            if let detail = entry.detail {
                                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(5)
                            }
                            Text("#\(entry.sequence) · \(shortTime(entry.timestamp))")
                                .font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 560)
    }

    private func shortTime(_ value: String) -> String {
        guard let date = ISOTime.formatter.date(from: value) else { return value }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Legacy approval alert (non-WhatsApp scenario only)

    private var approvalPresented: Binding<Bool> {
        Binding(get: { model.pendingAction != nil }, set: { if !$0 { model.cancelApproval() } })
    }
    private var approvalTitle: String { "Approve RocketRide execution?" }
    private var approvalConfirm: String { "Create draft" }
    private var approvalDetail: String {
        "This sends the approved intent to RocketRide to create an artifact. It will not send the outreach message."
    }
}

// MARK: - Animated accents

/// Top-left "Onari is running" pulse — the honesty indicator.
private struct RunningIndicator: View {
    let listening: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.28))
                    .frame(width: 24, height: 24)
                    .scaleEffect(pulse ? 1.7 : 0.85)
                    .opacity(pulse ? 0 : 0.9)
                Circle().fill(Color.green).frame(width: 12, height: 12)
            }
            .onAppear { withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true } }
            VStack(alignment: .leading, spacing: 1) {
                Text("Onari").font(.system(size: 20, weight: .bold))
                Text(listening ? "listening…" : "live · watching this session")
                    .font(.system(size: 13))
                    .foregroundStyle(listening ? Color.red : .secondary)
            }
        }
        .animation(.default, value: listening)
    }
}

/// Onari's avatar in the thread.
private struct OnariAvatar: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(
                LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
    }
}

/// Animated "typing" dots for an in-flight Onari reply. Self-contained so the
/// animation only runs while this view is on screen.
private struct TypingDots: View {
    @State private var animate = false
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle().fill(.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animate ? 1 : 0.5)
                    .opacity(animate ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.18),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
        .frame(height: 14)
    }
}

/// Pulsing red recording dot — exists only while recording, so it stops cleanly.
private struct RecordingPulse: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.3))
                .frame(width: 22, height: 22)
                .scaleEffect(animate ? 1.7 : 0.9)
                .opacity(animate ? 0 : 0.9)
            Circle().fill(Color.red).frame(width: 12, height: 12)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) { animate = true } }
    }
}
