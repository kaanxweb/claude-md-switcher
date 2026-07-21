import Combine
import Sparkle

@MainActor
final class UpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let standardUpdaterController: SPUStandardUpdaterController

    init() {
        let standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.standardUpdaterController = standardUpdaterController

        standardUpdaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        standardUpdaterController.updater.checkForUpdates()
    }
}
