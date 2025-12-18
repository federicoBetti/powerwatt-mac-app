import Foundation
import Sparkle

final class UpdaterManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    #if DEBUG
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard let override = UserDefaults.standard.string(forKey: "debug_appcast_url") else { return nil }
        guard let url = URL(string: override), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url.absoluteString
    }
    #endif
}



