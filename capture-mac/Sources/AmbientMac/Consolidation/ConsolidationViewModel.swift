import Foundation

@MainActor
final class ConsolidationViewModel: ObservableObject {
    @Published var response: ConsolidationResponse?
    @Published var draftMessage = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingAction: ConsolidationResponse.SuggestedAction?
    @Published var result: DispatchResult?

    let store: SessionStore
    private let service: Lane3Serving

    init(store: SessionStore, service: Lane3Serving = Lane3Client()) {
        self.store = store
        self.service = service
    }

    func consolidate() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let response = try await service.consolidate(sessionId: store.session.id)
                self.response = response
                store.append(type: "guild.response", title: "New session insight", detail: response.summary)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
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
    }

    func ask() {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        draftMessage = ""
        store.addChat(role: .user, text: text)
        isLoading = true
        Task {
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

    func requestApproval(for action: ConsolidationResponse.SuggestedAction) {
        pendingAction = action
    }

    func cancelApproval() {
        pendingAction = nil
    }

    func approve() {
        guard let response, let action = pendingAction, !isLoading else { return }
        pendingAction = nil
        isLoading = true
        store.append(type: "action.approved", title: action.label, detail: "Approved by user")
        Task {
            do {
                let result = try await service.dispatch(
                    sessionId: store.session.id,
                    response: response,
                    action: action
                )
                self.result = result
                store.recordDispatch(result)
            } catch {
                errorMessage = error.localizedDescription
                store.append(type: "dispatch.failed", title: "Dispatch failed", detail: error.localizedDescription)
            }
            isLoading = false
        }
    }
}
