import AppKit
import FinderSync
import RightClickCore

@MainActor
final class AppModel: ObservableObject {
    @Published var terminalProfile: TerminalProfile {
        didSet { SharedSettings.shared.terminalProfile = terminalProfile }
    }
    @Published var lastStatus = "等待 Finder 操作"
    @Published var lastError: String?

    private let requestStore = RequestStore()
    private let executor = ActionExecutor()

    init() {
        terminalProfile = SharedSettings.shared.terminalProfile
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func handle(url: URL) {
        guard url.scheme == AppConstants.deepLinkScheme,
              url.host == "perform",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idValue = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idValue) else {
            return
        }

        do {
            let request = try requestStore.take(id: id)
            try executor.execute(request, terminalProfile: terminalProfile)
            lastStatus = request.action.title
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
