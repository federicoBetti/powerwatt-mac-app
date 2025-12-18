import AppKit
import Foundation
import PostHog

final class TelemetryManager: ObservableObject {
    static let shared = TelemetryManager()

    private let installIdKey = "install_id"
    private let keychainService: String

    private var didSetupSDK = false
    private var didSendAppLaunch = false

    private var sessionEventCount = 0
    private let maxEventsPerSession = 200

    private var lastEventTimestamps: [String: Date] = [:]
    private let dedupeWindowSeconds: TimeInterval = 5

    private init() {
        self.keychainService = Bundle.main.bundleIdentifier ?? "PowerWatt"
    }

    var installID: String {
        if let existing = KeychainStore.readString(service: keychainService, key: installIdKey) {
            return existing
        }
        let newValue = UUID().uuidString
        _ = KeychainStore.writeString(service: keychainService, key: installIdKey, value: newValue)
        return newValue
    }

    func handleAppLaunch() {
        guard !didSendAppLaunch else { return }
        didSendAppLaunch = true

        if !AppSettings.shared.telemetryPromptShown {
            presentConsentPrompt()
        }

        if AppSettings.shared.telemetryEnabled {
            capture(event: "app_launch", properties: [:])
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard setupIfNeeded() else { return }
            AppSettings.shared.telemetryEnabled = true
            PostHogSDK.shared.optIn()
            capture(event: "app_first_launch", properties: [:])
        } else {
            AppSettings.shared.telemetryEnabled = false
            guard didSetupSDK else { return }
            PostHogSDK.shared.optOut()
            PostHogSDK.shared.reset()
            PostHogSDK.shared.flush()
        }
    }

    func capture(event: String, properties: [String: Any]) {
        guard AppSettings.shared.telemetryEnabled else { return }
        guard sessionEventCount < maxEventsPerSession else { return }

        let now = Date()
        let dedupeKey = makeDedupeKey(event: event, properties: properties)
        if let lastDate = lastEventTimestamps[dedupeKey], now.timeIntervalSince(lastDate) < dedupeWindowSeconds {
            return
        }
        lastEventTimestamps[dedupeKey] = now

        guard setupIfNeeded() else { return }

        sessionEventCount += 1
        PostHogSDK.shared.capture(event, properties: commonProperties().merging(properties) { _, new in new })
    }

    func openPrivacyPage() {
        guard let url = URL(string: "https://federicoBetti.github.io/powerwatt-mac-app/privacy.html") else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    private func setupIfNeeded() -> Bool {
        guard !didSetupSDK else { return true }
        guard let apiKey = posthogApiKey else { return false }
        didSetupSDK = true

        let config = PostHogConfig(apiKey: apiKey, host: posthogHost)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false

        PostHogSDK.shared.setup(config)
        return true
    }

    private func presentConsentPrompt() {
        AppSettings.shared.telemetryPromptShown = true

        let alert = NSAlert()
        alert.messageText = "Help improve PowerWatt"
        alert.informativeText = "Share anonymous usage statistics to help improve PowerWatt. This is optional and off by default."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Share anonymous usage stats")
        alert.addButton(withTitle: "Not now")
        alert.addButton(withTitle: "Learn more")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            setEnabled(true)
        case .alertThirdButtonReturn:
            openPrivacyPage()
        default:
            break
        }
    }

    private func commonProperties() -> [String: Any] {
        var props: [String: Any] = [:]
        props["install_id"] = installID
        props["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        props["build"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        props["macos_version"] = ProcessInfo.processInfo.operatingSystemVersionString
        props["locale"] = Locale.current.identifier
        return props
    }

    private func makeDedupeKey(event: String, properties: [String: Any]) -> String {
        let sorted = properties.keys.sorted().map { key in
            let value = properties[key].map { String(describing: $0) } ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&")
        return "\(event)|\(sorted)"
    }
}

private extension TelemetryManager {
    var posthogApiKey: String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return rawValue
    }

    var posthogHost: String {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "https://eu.i.posthog.com"
        }
        return rawValue
    }
}


