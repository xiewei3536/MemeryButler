import Foundation
import AppKit
import UserNotifications
import CryptoKit

/// 只接受本專案的正式 Release；驗證下載與 App 後，才在同磁碟原子換版。
@MainActor
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle, checking, upToDate
        case available(String)
        case downloading(Double)
        case installing, restarting
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var availableVersion: String?
    private var asset: Asset?
    private var checkTimer: DispatchSourceTimer?
    private let settings: SettingsStore
    private static let repo = "xiewei3536/MemeryButler"
    nonisolated static let bundleID = "com.bowei.memorybutler"
    nonisolated static let maxDownloadSize: Int64 = 128 << 20

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
        let digest: String?
    }
    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    static var isBundled: Bool { Bundle.main.bundleIdentifier == bundleID }

    init(settings: SettingsStore) {
        self.settings = settings
        guard !SelfTest.isEnabled else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 15, repeating: 6 * 3600, leeway: .seconds(30))
        t.setEventHandler { [weak self] in
            guard let self, self.settings.autoUpdateCheck else { return }
            Task { await self.check(userInitiated: false) }
        }
        t.resume()
        checkTimer = t
    }

    var updateAvailable: Bool {
        switch status {
        case .available, .downloading, .installing, .restarting: return true
        default: return false
        }
    }

    func check(userInitiated: Bool) async {
        switch status {
        case .checking, .downloading, .installing, .restarting: return
        default: break
        }
        status = .checking
        availableVersion = nil
        asset = nil
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("MemoryButler/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            guard !release.draft, !release.prerelease, Self.versionParts(latest) != nil else {
                throw UpdateError.invalidRelease
            }
            guard Self.isNewer(latest, than: Self.currentVersion) else {
                status = .upToDate
                resetSoon(after: 5)
                return
            }
            guard let dmg = release.assets.first(where: { $0.name == "MemoryButler.dmg" }),
                  dmg.size > 0, dmg.size <= Self.maxDownloadSize,
                  Self.approvedDownloadURL(dmg.browser_download_url) != nil,
                  Self.validDigest(dmg.digest) else { throw UpdateError.invalidRelease }
            asset = dmg
            availableVersion = latest
            status = .available(latest)
            postNotificationIfNeeded(version: latest)
        } catch {
            status = userInitiated ? .failed(error.localizedDescription) : .idle
            if userInitiated { resetSoon(after: 8) }
        }
    }

    nonisolated static func versionParts(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        guard let pa = versionParts(a), let pb = versionParts(b) else { return false }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func approvedDownloadURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              url.query == nil, url.fragment == nil,
              url.path.hasPrefix("/xiewei3536/MemeryButler/releases/download/"),
              !url.pathComponents.contains(".."), url.lastPathComponent == "MemoryButler.dmg" else { return nil }
        return url
    }

    nonisolated static func validDigest(_ digest: String?) -> Bool {
        guard let digest else { return true }  // 舊 Release 可能尚無 digest；仍驗證 HTTPS、大小與 App 簽章
        guard digest.hasPrefix("sha256:") else { return false }
        let hex = digest.dropFirst(7)
        return hex.count == 64 && hex.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    nonisolated static func validateDownload(at file: URL, size: Int64, digest: String?) throws {
        let actual = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard size > 0, size <= maxDownloadSize, actual?.int64Value == size, validDigest(digest) else {
            throw UpdateError.verificationFailed
        }
        guard let digest else { return }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == "sha256:" + hex else { throw UpdateError.verificationFailed }
    }

    // MARK: 系統通知（每個版本只通知一次，測試不碰通知或正式狀態）

    private func postNotificationIfNeeded(version: String) {
        guard Self.isBundled, !SelfTest.isEnabled else { return }
        let key = "lastNotifiedVersion"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        UserDefaults.standard.set(version, forKey: key)
        let content = UNMutableNotificationContent()
        content.title = L("update.notif.title")
        content.body = LF("update.notif.body", version)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "update-\(version)", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { center.add(request) }
        }
    }

    // MARK: 下載、驗證、安裝

    func downloadAndInstall() async {
        guard case .available(let version) = status, let asset,
              let url = Self.approvedDownloadURL(asset.browser_download_url) else { return }
        guard Self.isBundled else {
            status = .failed(L("update.dev")); resetSoon(after: 5); return
        }
        status = .downloading(0)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MemoryButler-update-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let dmg = work.appendingPathComponent("MemoryButler.dmg")
            let progress = DownloadProgress(destination: dmg) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = self.status else { return }
                    self.status = .downloading(fraction)
                }
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 60
            let (file, response) = try await URLSession.shared.download(for: req, delegate: progress)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            if !FileManager.default.fileExists(atPath: dmg.path) { try FileManager.default.moveItem(at: file, to: dmg) }
            status = .installing
            try await Task.detached(priority: .utility) {
                try Self.validateDownload(at: dmg, size: asset.size, digest: asset.digest)
            }.value
            try await Self.install(dmg: dmg, expectedVersion: version)
            try? FileManager.default.removeItem(at: work) // terminate 可能直接結束程序，先清掉已用完的 DMG
            status = .restarting
            try relaunch()
        } catch {
            status = .failed(error.localizedDescription)
            resetSoon(after: 8)
        }
    }

    nonisolated static func validBundleMetadata(identifier: String?, version: String?, expectedVersion: String) -> Bool {
        identifier == bundleID && version == expectedVersion && versionParts(expectedVersion) != nil
    }

    nonisolated private static func install(dmg: URL, expectedVersion: String) async throws {
        let bundle = URL(fileURLWithPath: Bundle.main.bundlePath)
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let mount = fm.temporaryDirectory.appendingPathComponent("MemoryButler-mount-\(UUID().uuidString)")
            try fm.createDirectory(at: mount, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: mount) }
            _ = try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
            let newApp = mount.appendingPathComponent("MemoryButler.app")
            guard let info = Bundle(url: newApp),
                  validBundleMetadata(identifier: info.bundleIdentifier,
                                      version: info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                      expectedVersion: expectedVersion),
                  fm.isExecutableFile(atPath: newApp.appendingPathComponent("Contents/MacOS/MemoryButler").path) else {
                throw UpdateError.verificationFailed
            }
            // 先完整複製、驗證到同一磁碟上的暫存 App；原版仍在原位，失敗不會留下半套 App。
            let parent = bundle.deletingLastPathComponent()
            let staging = parent.appendingPathComponent(".MemoryButler-stage-\(UUID().uuidString).app")
            let backup = parent.appendingPathComponent(".MemoryButler-backup-\(UUID().uuidString).app")
            defer { try? fm.removeItem(at: staging) }
            _ = try run("/usr/bin/ditto", [newApp.path, staging.path])
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staging.path])
            try fm.moveItem(at: bundle, to: backup)
            do {
                try fm.moveItem(at: staging, to: bundle)
            } catch {
                try? fm.moveItem(at: backup, to: bundle) // 回復失敗時保留備份，不刪除唯一可用的舊版
                throw error
            }
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", bundle.path])
            try? fm.removeItem(at: backup)
        }.value
    }

    /// 路徑只當作參數，不插入 shell；等舊實例退出後再啟動，不靠固定 1 秒猜測。
    private func relaunch() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n \"$2\"",
                       "memorybutler-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        NSApp.terminate(nil)
    }

    private func resetSoon(after seconds: UInt64) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self else { return }
            switch self.status {
            case .upToDate, .failed: self.status = .idle
            default: break
            }
        }
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        // 先讀再 wait，工具輸出超過 pipe 容量時才不會雙方互等。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw UpdateError.toolFailed(tool: (tool as NSString).lastPathComponent, output: output)
        }
        return output
    }

    enum UpdateError: LocalizedError {
        case invalidRelease, verificationFailed
        case badResponse(Int)
        case toolFailed(tool: String, output: String)
        var errorDescription: String? {
            switch self {
            case .invalidRelease: return L("update.invalidRelease")
            case .verificationFailed: return L("update.verificationFailed")
            case .badResponse(let code): return "HTTP \(code)"
            case .toolFailed(let tool, let output): return "\(tool): \(String(output.suffix(120)))"
            }
        }
    }
}

/// 背景寫檔，最多每 2% 更新一次畫面，不讓下載封包的頻率變成主執行緒的重繪頻率。
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: (Double) -> Void
    private let lock = NSLock()
    private var lastFraction = -1.0

    init(destination: URL, onProgress: @escaping (Double) -> Void) {
        self.destination = destination; self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= Updater.maxDownloadSize,
              totalBytesExpectedToWrite <= Updater.maxDownloadSize else { downloadTask.cancel(); return }
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        lock.lock()
        let changed = fraction - lastFraction >= 0.02 || (fraction == 1 && lastFraction < 1)
        if changed { lastFraction = fraction }
        lock.unlock()
        if changed { onProgress(fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        try? FileManager.default.moveItem(at: location, to: destination)
    }
}
