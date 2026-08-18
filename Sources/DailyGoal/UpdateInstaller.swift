import AppKit
import CryptoKit
import Security

/// Downloads a release DMG from GitHub, proves it's genuine, and swaps the
/// running app for the new version. Two independent checks gate the install:
/// the DMG's SHA-256 must match the checksum published with the release, and
/// the new bundle must carry a valid Developer ID signature for this app's
/// team and bundle identifier. Any failure aborts before the old app is
/// touched and offers the plain download page instead.
final class UpdateInstaller {
    static let shared = UpdateInstaller()

    private static let teamID = "S5NQXKYPKT"
    private static let bundleID = "org.gipplab.dailygoal"

    private let queue = DispatchQueue(label: "UpdateInstaller", qos: .userInitiated)
    private var running = false

    /// Runs the whole pipeline on a background queue, driving a small
    /// progress window, then relaunches into the new version. Call on main.
    func install(version: String, dmgURL: URL, checksumURL: URL) {
        guard !running else { return }
        running = true

        let destination = Bundle.main.bundleURL
        let window = ProgressWindow(title: "Updating Daily Goal")
        window.show(status: "Downloading Daily Goal \(version)…")

        queue.async {
            do {
                try Self.ensureReplaceable(destination)

                let workDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("DailyGoalUpdate-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: workDir) }

                let checksum = try Self.fetchChecksum(checksumURL)
                let dmg = workDir.appendingPathComponent("DailyGoal.dmg")
                try Self.download(dmgURL, to: dmg) { fraction in
                    DispatchQueue.main.async {
                        window.update(status: "Downloading Daily Goal \(version)…", fraction: fraction)
                    }
                }

                DispatchQueue.main.async { window.update(status: "Verifying download…", fraction: nil) }
                guard try Self.sha256(of: dmg) == checksum else { throw Failure.checksumMismatch }

                let staged = workDir.appendingPathComponent("Daily Goal.app")
                try Self.extractApp(from: dmg, to: staged)
                try Self.verifySignature(of: staged)
                try Self.verifyVersion(of: staged, expected: version)

                DispatchQueue.main.async { window.update(status: "Installing…", fraction: nil) }
                try Self.replace(destination, with: staged, retiringOldInto: workDir)

                DispatchQueue.main.async {
                    window.close()
                    self.running = false
                    Self.relaunch(destination)
                }
            } catch {
                DispatchQueue.main.async {
                    window.close()
                    self.running = false
                    Self.reportFailure(error)
                }
            }
        }
    }

    // MARK: - Pipeline steps

    private enum Failure: LocalizedError {
        case notInstalled
        case notWritable(String)
        case badServerResponse
        case checksumMismatch
        case noAppInImage
        case unsigned(String)
        case wrongVersion(String)
        case tool(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Daily Goal is running from a disk image or a temporary location. "
                    + "Move it to your Applications folder and try again."
            case .notWritable(let dir):
                return "The folder \(dir) isn't writable, so the app can't replace itself there."
            case .badServerResponse:
                return "GitHub returned an unexpected response. Try again later."
            case .checksumMismatch:
                return "The downloaded file doesn't match the checksum published with the "
                    + "release, so it was discarded."
            case .noAppInImage:
                return "The downloaded disk image doesn't contain the app."
            case .unsigned(let detail):
                return "The download isn't signed by the Daily Goal developer "
                    + "(\(detail)), so it was discarded."
            case .wrongVersion(let expected):
                return "The downloaded app isn't version \(expected), so it was discarded."
            case .tool(let detail):
                return "A system tool failed while installing (\(detail))."
            }
        }
    }

    /// Self-replacement only makes sense for a real install: not translocated,
    /// not on a read-only volume, and in a folder we can write to.
    private static func ensureReplaceable(_ bundle: URL) throws {
        if bundle.path.contains("/AppTranslocation/") || bundle.path.hasPrefix("/Volumes/") {
            throw Failure.notInstalled
        }
        let fm = FileManager.default
        let parent = bundle.deletingLastPathComponent().path
        guard fm.isWritableFile(atPath: parent), fm.isWritableFile(atPath: bundle.path) else {
            throw Failure.notWritable(parent)
        }
    }

    /// The published checksum file: "<64 hex chars>  DailyGoal.dmg".
    private static func fetchChecksum(_ url: URL) throws -> String {
        let data = try get(url)
        guard let text = String(data: data, encoding: .utf8),
              let token = text.split(whereSeparator: \.isWhitespace).first,
              token.count == 64, token.allSatisfy(\.isHexDigit) else {
            throw Failure.badServerResponse
        }
        return token.lowercased()
    }

    /// Blocking GET, for the queue this runs on.
    private static func get(_ url: URL) throws -> Data {
        var result: Result<Data, Error> = .failure(Failure.badServerResponse)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(Failure.badServerResponse)
            } else if let data {
                result = .success(data)
            }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }

    /// Blocking file download with byte-level progress (0…1).
    private static func download(_ url: URL, to destination: URL,
                                 progress: @escaping (Double) -> Void) throws {
        final class Delegate: NSObject, URLSessionDownloadDelegate {
            let destination: URL
            let progress: (Double) -> Void
            let done = DispatchSemaphore(value: 0)
            var failure: Error?

            init(destination: URL, progress: @escaping (Double) -> Void) {
                self.destination = destination
                self.progress = progress
            }

            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                            didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                            totalBytesExpectedToWrite: Int64) {
                guard totalBytesExpectedToWrite > 0 else { return }
                progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }

            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                            didFinishDownloadingTo location: URL) {
                do {
                    if let http = downloadTask.response as? HTTPURLResponse,
                       !(200..<300).contains(http.statusCode) {
                        throw Failure.badServerResponse
                    }
                    try FileManager.default.moveItem(at: location, to: destination)
                } catch {
                    failure = error
                }
            }

            func urlSession(_ session: URLSession, task: URLSessionTask,
                            didCompleteWithError error: Error?) {
                if let error, failure == nil { failure = error }
                done.signal()
            }
        }

        let delegate = Delegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        session.downloadTask(with: url).resume()
        delegate.done.wait()
        session.finishTasksAndInvalidate()
        if let failure = delegate.failure { throw failure }
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Mounts the DMG, copies the one app inside to `staged`, unmounts.
    private static func extractApp(from dmg: URL, to staged: URL) throws {
        let plist = try run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-plist")
        guard let attach = try? PropertyListSerialization.propertyList(from: plist, format: nil),
              let entities = (attach as? [String: Any])?["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw Failure.tool("hdiutil reported no mount point")
        }
        defer { _ = try? run("/usr/bin/hdiutil", "detach", mountPoint, "-force") }

        let contents = try FileManager.default.contentsOfDirectory(atPath: mountPoint)
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw Failure.noAppInImage
        }
        // ditto preserves symlinks, permissions, and extended attributes, so
        // the copy's code signature stays byte-for-byte valid.
        try run("/usr/bin/ditto", mountPoint + "/" + appName, staged.path)
    }

    /// The bundle must satisfy: signed with a Developer ID certificate,
    /// issued to this app's team, for this app's bundle identifier.
    private static func verifySignature(of app: URL) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            throw Failure.unsigned("the signature couldn't be read")
        }
        let requirementText = "anchor apple generic"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"  // Developer ID Application
            + " and certificate leaf[subject.OU] = \"\(teamID)\""
            + " and identifier \"\(bundleID)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            throw Failure.unsigned("the signing requirement couldn't be built")
        }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures)
            | UInt32(kSecCSStrictValidate) | UInt32(kSecCSCheckNestedCode))
        let status = SecStaticCodeCheckValidity(code, flags, req)
        guard status == errSecSuccess else {
            throw Failure.unsigned("check failed with code \(status)")
        }
    }

    private static func verifyVersion(of app: URL, expected: String) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              info["CFBundleShortVersionString"] as? String == expected else {
            throw Failure.wrongVersion(expected)
        }
    }

    /// The swap: retire the old bundle into the temp dir, move the new one
    /// into place. Rolls the old one back if the second move fails.
    private static func replace(_ destination: URL, with staged: URL,
                                retiringOldInto workDir: URL) throws {
        let fm = FileManager.default
        let retired = workDir.appendingPathComponent("previous.app")
        try fm.moveItem(at: destination, to: retired)
        do {
            try fm.moveItem(at: staged, to: destination)
        } catch {
            try? fm.moveItem(at: retired, to: destination)
            throw error
        }
    }

    /// A detached shell waits for this process to exit, then opens the new
    /// version. `open` resolves the fresh bundle, not our dying process.
    private static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; "
            + "/usr/bin/open \"\(app.path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: String...) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.tool("\((tool as NSString).lastPathComponent) exited "
                + "with status \(process.terminationStatus)")
        }
        return output
    }

    private static func reportFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't install the update"
        alert.informativeText = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            UpdateChecker.shared.openDownloadPage()
        }
    }
}

/// A small floating window with one status line and a progress bar.
private final class ProgressWindow {
    private let window: NSWindow
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()

    init(title: String) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 84),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = title
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()

        label.frame = NSRect(x: 20, y: 48, width: 340, height: 18)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        bar.frame = NSRect(x: 20, y: 20, width: 340, height: 20)
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.isIndeterminate = true
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(bar)
    }

    func show(status: String) {
        update(status: status, fraction: nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// A nil fraction switches the bar to indeterminate (barber pole).
    func update(status: String, fraction: Double?) {
        label.stringValue = status
        if let fraction {
            bar.isIndeterminate = false
            bar.doubleValue = fraction
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
    }

    func close() {
        window.close()
    }
}
