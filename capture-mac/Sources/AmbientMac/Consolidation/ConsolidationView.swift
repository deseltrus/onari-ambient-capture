import SwiftUI

struct ConsolidationView: View {
    @ObservedObject var model: ConsolidationViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .padding(.horizontal, 30)
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            chatBar
        }
        .frame(minWidth: 760, minHeight: 680)
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
            if model.isLoading { ProgressView().controlSize(.small) }
            Button {
                model.showTimeline = true
            } label: {
                Label("Activity", systemImage: "list.bullet.rectangle")
            }
            .help("Session events & timeline")
            Button {
                model.consolidate()
            } label: {
                Label("Rethink", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model.isLoading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red)
                .padding(14)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 8)
        }

        if model.response == nil && model.isLoading {
            loadingView
        } else if let response = model.response {
            insight(response)
        } else {
            emptyState
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ThinkingIcon()
            Text(model.loadingStage ?? "Thinking…")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
                .id(model.loadingStage)
                .animation(.easeInOut(duration: 0.35), value: model.loadingStage)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "No session insight yet",
                systemImage: "sparkles",
                description: Text("Ask Onari to look back over this session and connect it to your memory.")
            )
            Button {
                model.consolidate()
            } label: {
                Text("Analyze this session").font(.system(size: 17, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    private func insight(_ response: ConsolidationResponse) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT ONARI NOTICED")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Text(response.summary)
                    .font(.system(size: 26, weight: .semibold))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("WHY THIS SURFACED")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                ForEach(response.evidence) { evidence in
                    evidenceRow(evidence)
                }
            }

            HStack(spacing: 14) {
                Button("Save insight") { model.save() }
                    .controlSize(.large)
                Button("Ignore", role: .destructive) { model.ignore() }
                    .controlSize(.large)
                Spacer()
            }

            suggestedActionArea(response)

            if model.isDispatching || !model.executionSteps.isEmpty {
                pipelineView
            }

            if let result = model.result, let artifact = result.artifact {
                resultView(result: result, artifact: artifact)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: model.showAction)
        .animation(.easeInOut(duration: 0.3), value: model.isReasoningAction)
        .animation(.easeInOut(duration: 0.35), value: model.executionSteps.count)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.result)
    }

    private func evidenceRow(_ evidence: ConsolidationResponse.Evidence) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: evidence.kind == "unspoken_board" ? "eye.fill"
                  : evidence.kind == "history_join" ? "clock.arrow.circlepath" : "note.text")
                .font(.system(size: 18))
                .foregroundStyle(evidence.kind == "unspoken_board" ? .purple
                                 : evidence.kind == "history_join" ? .blue : .teal)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(evidence.label).font(.system(size: 17, weight: .semibold))
                    if evidence.kind == "unspoken_board" {
                        Text("UNSPOKEN")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.purple.opacity(0.16), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }
                Text(evidence.detail)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Suggested action (reasoned reveal)

    @ViewBuilder
    private func suggestedActionArea(_ response: ConsolidationResponse) -> some View {
        if let action = response.suggestedActions.first {
            if model.isReasoningAction {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Onari is deciding what would help…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .transition(.opacity)
            }

            if model.showAction {
                actionCard(action)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            }
        }
    }

    private func actionCard(_ action: ConsolidationResponse.SuggestedAction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                Text("Onari suggests").font(.system(size: 15, weight: .bold)).foregroundStyle(.purple)
                Spacer()
                Text("⌃⌥⌘↩ to send")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }
            Button {
                model.performAction(action)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paperplane.fill").font(.system(size: 18))
                    Text(action.label).font(.system(size: 18, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isLoading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.purple.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.purple.opacity(0.25), lineWidth: 1))
        )
    }

    // MARK: - Execution pipeline

    private var pipelineView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(.orange)
                Text("RocketRide execution pipeline").font(.system(size: 17, weight: .semibold))
                if model.isDispatching { ProgressView().controlSize(.small) }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.executionSteps) { step in
                    stepRow(step)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stepRow(_ step: ExecutionStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            stepIcon(for: step.status).font(.system(size: 17)).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.label).font(.system(size: 16, weight: .semibold))
                if let detail = step.detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
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

    // MARK: - Result (WhatsApp message)

    private func resultView(result: DispatchResult, artifact: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: result.status == "failed" ? "xmark.circle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(result.status == "failed" ? .red : .green)
                Text(result.status == "failed" ? "Dispatch \(result.status)" : "Sent to Hackathon 08/03 - TEAM O")
                    .font(.system(size: 17, weight: .semibold))
            }
            // WhatsApp-style bubble.
            HStack {
                Text(artifact)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .background(Color(red: 0.86, green: 0.97, blue: 0.86), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.black)
                Spacer(minLength: 30)
            }
            if let trace = result.traceURL, let url = URL(string: trace) {
                Link(destination: url) {
                    Label("Open RocketRide execution trace", systemImage: "arrow.up.forward.square")
                        .font(.system(size: 14, weight: .medium))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    // MARK: - Chat bar with voice

    private var chatBar: some View {
        VStack(spacing: 8) {
            if let latest = model.store.chat.last {
                HStack(alignment: .top, spacing: 8) {
                    Text(latest.role == .user ? "You" : "Onari")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(latest.role == .user ? Color.primary : Color.purple)
                    Text(latest.text).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
            }
            HStack(spacing: 12) {
                Button {
                    model.toggleVoice()
                } label: {
                    Image(systemName: model.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(model.isRecording ? .red : Color.accentColor)
                        .scaleEffect(model.isRecording ? 1.12 : 1)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: model.isRecording)
                }
                .buttonStyle(.plain)
                .help("Hold a thought — speak to Onari")

                TextField(model.isRecording ? "Listening…" : "Ask Onari about this session…", text: $model.draftMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit { model.ask() }

                Button("Send") { model.ask() }
                    .controlSize(.large)
                    .disabled(model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
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
        Binding(
            get: { model.pendingAction != nil },
            set: { if !$0 { model.cancelApproval() } }
        )
    }

    private var approvalTitle: String { "Approve RocketRide execution?" }
    private var approvalConfirm: String { "Create draft" }
    private var approvalDetail: String {
        "This sends the approved intent to RocketRide to create an artifact. It will not send the outreach message."
    }
}

// MARK: - Animated accents

/// Top-left "Onari is running" pulse. The green dot doubles as the honesty
/// indicator from the menu bar: if it is pulsing, capture is live.
private struct RunningIndicator: View {
    let listening: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.28))
                    .frame(width: 24, height: 24)
                    .scaleEffect(pulse ? 1.7 : 0.85)
                    .opacity(pulse ? 0 : 0.9)
                Circle().fill(Color.green).frame(width: 12, height: 12)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true }
            }
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

/// The "thinking" glyph for the staged loading screen.
private struct ThinkingIcon: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 48))
            .foregroundStyle(.purple)
            .scaleEffect(pulse ? 1.15 : 0.85)
            .opacity(pulse ? 1 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}
