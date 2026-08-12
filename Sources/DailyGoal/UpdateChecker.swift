import AppKit

/// The app's only network code: a single GET to the GitHub releases API to
/// learn the latest version number. Runs when asked from the menu, or (unless
/// turned off there) quietly at most once a day. Nothing is sent beyond the
/// request itself; installing an update is still a manual download.
final class UpdateChecker {
    static let shared = UpdateChecker()

    private static let api = URL(string: "https://api.github.com/repos/jpwahle/daily-goal/releases/latest")!
    private static let downloadPage = URL(string: "https://github.com/jpwahle/daily-goal/releases/latest")!
    private static let dailyKey = "updateCheckDaily"
    private static let lastCheckKey = "updateCheckLast"

    /// Newer version found by the last check (e.g. "1.2.0"), nil when current.
    private(set) var availableVersion: String?

    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var dailyChecksEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.dailyKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.dailyKey)
            if newValue { checkIfDue() }
        }
    }

    /// Call once at launch. Re-arms hourly so a Mac that never sleeps past
    /// midnight still checks roughly daily.
    func start() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(Self.downloadPage)
    }

    /// Menu action: check now and report the outcome either way.
    func checkInteractively() {
        check { result in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            switch result {
            case .success(.some(let newer)):
                alert.messageText = "Daily Goal \(newer) is available"
                alert.informativeText = "You have \(Self.currentVersion)."
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.openDownloadPage()
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
        guard dailyChecksEnabled else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= 86_400 else { return }
        check { _ in }
    }

    /// Completion runs on the main queue with the newer version, nil when
    /// already current, or the network/parse error.
    private func check(_ completion: @escaping (Result<String?, Error>) -> Void) {
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
                self.availableVersion = Self.isNewer(latest, than: Self.currentVersion) ? latest : nil
                completion(.success(self.availableVersion))
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
