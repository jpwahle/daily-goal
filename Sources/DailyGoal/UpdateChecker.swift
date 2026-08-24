import AppKit

/// Checks GitHub for a newer release. Runs when asked from the menu, or
/// (unless turned off there) quietly on its own: at most every 8 hours —
/// three times a day — and right after the Mac wakes, so sleeping through a
/// due time doesn't delay the catch. The only network traffic is to GitHub:
/// one GET to the releases API, and — only when the user chooses to install —
/// the release download itself. Nothing about the user is ever sent, and
/// nothing installs without an explicit click; the actual
/// download/verify/swap lives in UpdateInstaller.
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// A newer release, as learned from the GitHub API. The asset URLs are
    /// optional so a release that is missing the DMG or its checksum can
    /// still be announced — installing then falls back to the download page.
    struct AvailableUpdate {
        let version: String
        let dmgURL: URL?
        let checksumURL: URL?
    }

    private static let api = URL(string: "https://api.github.com/repos/jpwahle/daily-goal/releases/latest")!
    private static let downloadPage = URL(string: "https://github.com/jpwahle/daily-goal/releases/latest")!
    // Defaults key name predates the 8-hour cadence; kept so the setting
    // survives updates.
    private static let autoKey = "updateCheckDaily"
    private static let lastCheckKey = "updateCheckLast"
    /// Quiet checks fire at most this often — three per day.
    private static let checkEvery: TimeInterval = 8 * 3600

    /// Set by the last check when a newer release exists, nil when current.
    private(set) var available: AvailableUpdate?

    /// Newer version found by the last check (e.g. "1.2.0"), nil when current.
    var availableVersion: String? { available?.version }

    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var autoChecksEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoKey)
            if newValue { checkIfDue() }
        }
    }

    /// Call once at launch. The hourly timer only compares timestamps; the
    /// network request happens when a check is actually due.
    func start() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        timer?.tolerance = 300
        // Timers don't fire while the Mac sleeps, so a due check could
        // otherwise wait up to an hour after wake. Check on wake instead —
        // after a grace period, since Wi-Fi is often still reassociating.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                UpdateChecker.shared.checkIfDue()
            }
        }
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(Self.downloadPage)
    }

    /// Download, verify, and install the update found by the last check.
    /// Releases without a DMG + checksum can't be verified, so those open
    /// the download page instead.
    func installAvailableUpdate() {
        guard let update = available, let dmg = update.dmgURL, let sum = update.checksumURL else {
            openDownloadPage()
            return
        }
        UpdateInstaller.shared.install(version: update.version, dmgURL: dmg, checksumURL: sum)
    }

    /// Menu action: check now and report the outcome either way.
    func checkInteractively() {
        check { result in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            switch result {
            case .success(.some(let update)):
                alert.messageText = "Daily Goal \(update.version) is available"
                alert.informativeText = "You have \(Self.currentVersion). The update downloads "
                    + "from GitHub and is verified before it replaces the app."
                alert.addButton(withTitle: "Install Update")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.installAvailableUpdate()
                }
            case .success(.none):
                alert.messageText = "You're up to date"
                alert.informativeText = "Daily Goal \(Self.currentVersion) is the latest version."
                alert.runModal()
            case .failure:
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "GitHub wasn't reachable. Try again later."
                alert.runModal()
            }
        }
    }

    private func checkIfDue() {
        guard autoChecksEnabled else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= Self.checkEvery else { return }
        check { _ in }
    }

    /// Completion runs on the main queue with the newer release, nil when
    /// already current, or the network/parse error.
    private func check(_ completion: @escaping (Result<AvailableUpdate?, Error>) -> Void) {
        var request = URLRequest(url: Self.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    completion(.failure(URLError(.cannotParseResponse)))
                    return
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                if Self.isNewer(latest, than: Self.currentVersion) {
                    let assets = json["assets"] as? [[String: Any]] ?? []
                    func url(ofAssetNamed name: String) -> URL? {
                        for asset in assets where asset["name"] as? String == name {
                            if let s = asset["browser_download_url"] as? String { return URL(string: s) }
                        }
                        return nil
                    }
                    self.available = AvailableUpdate(
                        version: latest,
                        dmgURL: url(ofAssetNamed: "DailyGoal.dmg"),
                        checksumURL: url(ofAssetNamed: "DailyGoal.dmg.sha256"))
                } else {
                    self.available = nil
                }
                completion(.success(self.available))
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
