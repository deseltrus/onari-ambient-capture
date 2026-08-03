import SwiftUI

struct ConsolidationView: View {
    @ObservedObject var model: ConsolidationViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                sessionPane
                    .frame(minWidth: 490)
                timelinePane
                    .frame(minWidth: 260, idealWidth: 310)
            }
            Divider()
            chatBar
        }
        .frame(minWidth: 820, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Approve RocketRide execution?", isPresented: approvalPresented) {
            Button("Cancel", role: .cancel) { model.cancelApproval() }
            Button("Create draft") { model.approve() }
        } message: {
            Text("This sends the approved intent to RocketRide to create an artifact. It will not send the outreach message.")
        }
    }

    private var approvalPresented: Binding<Bool> {
        Binding(
            get: { model.pendingAction != nil },
            set: { if !$0 { model.cancelApproval() } }
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.green).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text("Session intelligence").font(.headline)
                Text(model.store.session.id).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
            Button("Refresh from memory") { model.consolidate() }
                .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(16)
    }

    private var sessionPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding(12)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if let response = model.response {
                    Text("What Onari noticed")
                        .font(.title2.bold())
                    Text(response.summary)
                        .font(.title3)
                        .textSelection(.enabled)

                    Text("WHY THIS SURFACED")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(response.evidence) { evidence in
                        evidenceRow(evidence)
                    }

                    HStack {
                        Button("Save insight") { model.save() }
                        Button("Ignore", role: .destructive) { model.ignore() }
                        Spacer()
                    }

                    if !response.suggestedActions.isEmpty {
                        Divider()
                        Text("Suggested action").font(.headline)
                        ForEach(response.suggestedActions) { action in
                            Button {
                                model.requestApproval(for: action)
                            } label: {
                                Label(action.label, systemImage: "bolt.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No session insight yet",
                        systemImage: "sparkles",
                        description: Text("Load the latest FalkorDB intent frame and ask the Guild layer to assemble the session.")
                    )
                    Button("Analyze this session") { model.consolidate() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }

                if let result = model.result, let artifact = result.artifact {
                    Divider()
                    Label("RocketRide result", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(artifact)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    if let trace = result.traceURL, let url = URL(string: trace) {
                        Link("Open execution trace", destination: url)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func evidenceRow(_ evidence: ConsolidationResponse.Evidence) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: evidence.kind == "unspoken_board" ? "eye.fill" : "clock.arrow.circlepath")
                .foregroundStyle(evidence.kind == "unspoken_board" ? .purple : .blue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(evidence.label).font(.headline)
                    if evidence.kind == "unspoken_board" {
                        Text("UNSPOKEN")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.purple.opacity(0.14), in: Capsule())
                    }
                }
                Text(evidence.detail).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var timelinePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Session timeline")
                .font(.headline)
                .padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.store.timeline.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title).font(.subheadline.bold())
                            if let detail = entry.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                            }
                            Text("#\(entry.sequence) · \(shortTime(entry.timestamp))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var chatBar: some View {
        VStack(spacing: 8) {
            if let latest = model.store.chat.last {
                HStack(alignment: .top) {
                    Text(latest.role == .user ? "You" : "Onari").font(.caption.bold())
                    Text(latest.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
            }
            HStack {
                TextField("Ask about this session…", text: $model.draftMessage)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.ask() }
                Button("Send") { model.ask() }
                    .disabled(model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }

    private func shortTime(_ value: String) -> String {
        guard let date = ISOTime.formatter.date(from: value) else { return value }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
