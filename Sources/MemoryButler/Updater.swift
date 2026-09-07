import Foundation
import AppKit
import UserNotifications

/// 自動更新:定期查 GitHub Releases → 系統通知 → App 內一鍵下載安裝並重啟。
@MainActor
final class Updater: ObservableObject {

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)      // 新版本號
        case downloading(Double)    // 0...1
        case installing
        case restarting
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var availableVersion: String?

    private var dmgDownloadURL: URL?
    private var checkTimer: DispatchSourceTimer?
    private let settings: SettingsStore
    private static let repo = "xiewei3536/MemeryButler"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    init(settings: SettingsStore) {
        self.settings = settings

        // 啟動 15 秒後靜默檢查一次,之後每 6 小時
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 15, repeating: 6 * 3600)
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

    // MARK: - 檢查

    func check(userInitiated: Bool) async {
        switch status {
        case .checking, .downloading, .installing, .restarting: return
        default: break
        }
        status = .checking

        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: String }
            let tag_name: String
            let assets: [Asset]
        }

        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: req)
            let rel = try JSONDecoder().decode(Release.self, from: data)
            let latest = rel.tag_name.hasPrefix("v") ? String(rel.tag_name.dropFirst()) : rel.tag_name

            if let dmg = rel.assets.first(where: { $0.name.hasSuffix(".dmg") }),
               Self.isNewer(latest, than: Self.currentVersion) {
                availableVersion = latest
                dmgDownloadURL = URL(string: dmg.browser_download_url)
                status = .available(latest)
                postNotificationIfNeeded(version: latest)
            } else {
                status = .upToDate
                resetSoon(after: 5)
            }
        } catch {
            if userInitiated {
                status = .failed(error.localizedDescription)
                resetSoon(after: 8)
            } else {
                status = .idle
            }
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - 系統通知（每個版本只推播一次）

    private func postNotificationIfNeeded(version: String) {
        guard Self.isBundled else { return }
        let key = "lastNotifiedVersion"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        UserDefaults.standard.set(version, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = L("update.notif.title")
        content.body = LF("update.notif.body", version)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "update-\(version)", content: content, trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { center.add(request) }
        }
    }

    // MARK: - 下載並安裝

    func downloadAndInstall() async {
        guard let url = dmgDownloadURL, availableVersion != nil else { return }
        guard Self.isBundled else {
            status = .failed(L("update.dev"))
            resetSoon(after: 5)
            return
        }
        status = .downloading(0)

        do {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("MemoryButler-update.dmg")
            try? FileManager.default.removeItem(at: tmp)

            // 交給系統的下載工作：背景寫檔、委派回報進度，主執行緒完全不碰資料流
            //（舊作法逐位元組 for-await 在主執行緒迭代，下載期間整個面板會卡頓）
            let progress = DownloadProgress(destination: tmp) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = self.status else { return }
                    self.status = .downloading(fraction)
                }
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 60
            let (fileURL, response) = try await URLSession.shared.download(for: req, delegate: progress)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw UpdateError.badResponse(http.statusCode)
            }
            // 委派通常已把檔案搬到 tmp；若沒有（系統行為差異），這裡再搬一次
            if !FileManager.default.fileExists(atPath: tmp.path) {
                try FileManager.default.moveItem(at: fileURL, to: tmp)
            }

            status = .installing
            try await Self.install(dmg: tmp)

            status = .restarting
            relaunch()
        } catch {
            status = .failed(error.localizedDescription)
            resetSoon(after: 8)
        }
    }

    /// 掛載 DMG → 備份舊版 → 換入新版 → 去除隔離屬性 → 卸載;失敗自動還原。
    nonisolated private static func install(dmg: URL) async throws {
        let bundlePath = Bundle.main.bundlePath
        try await Task.detached(priority: .userInitiated) {
            let mount = NSTemporaryDirectory() + "MemoryButlerUpdateMount"
            _ = try? run("/usr/bin/hdiutil", ["detach", mount, "-force"])
            _ = try run("/usr/bin/hdiutil",
                        ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount])
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount, "-force"]) }

            let newApp = mount + "/MemoryButler.app"
            guard FileManager.default.fileExists(atPath: newApp) else {
                throw UpdateError.dmgMissingApp
            }

            let backup = NSTemporaryDirectory() + "MemoryButler-old-\(UUID().uuidString).app"
            try FileManager.default.moveItem(atPath: bundlePath, toPath: backup)
            do {
                _ = try run("/usr/bin/ditto", [newApp, bundlePath])
            } catch {
                try? FileManager.default.removeItem(atPath: bundlePath)
                try? FileManager.default.moveItem(atPath: backup, toPath: bundlePath)
                throw error
            }
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", bundlePath])
            try? FileManager.default.removeItem(atPath: backup)
        }.value
    }

    /// 舊實例結束 1 秒後由背景 shell 啟動新實例
    private func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"\(path)\""]
        try? p.run()   // 不等待,讓它在我們結束後接手

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            NSApp.terminate(nil)
        }
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
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw UpdateError.toolFailed(tool: (tool as NSString).lastPathComponent, output: out)
        }
        return out
    }

    enum UpdateError: LocalizedError {
        case dmgMissingApp
        case badResponse(Int)
        case toolFailed(tool: String, output: String)

        var errorDescription: String? {
            switch self {
            case .dmgMissingApp:
                return "DMG missing MemoryButler.app"
            case .badResponse(let code):
                return "HTTP \(code)"
            case .toolFailed(let tool, let output):
                return "\(tool): \(String(output.suffix(120)))"
            }
        }
    }
}

/// 下載進度委派：回報已寫入比例，並在完成當下就把檔案搬到目的地
///（系統可能在 didFinishDownloadingTo 回傳後立即刪除暫存檔）
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: (Double) -> Void

    init(destination: URL, onProgress: @escaping (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: location, to: destination)
    }
}
