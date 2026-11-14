#if !APP_STORE
import Sparkle
import SwiftUI

/// Owns the SPUUpdater for the lifetime of the app.
/// Initialize once in the @main App struct and hold a reference.
final class UpdaterController: ObservableObject {
    private let feedDelegate = UpdaterFeedDelegate()
    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: feedDelegate,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

/// Use the installed edition even when older releases persisted a shared feed override.
final class UpdaterFeedDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        updater.hostBundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }
}
#endif
