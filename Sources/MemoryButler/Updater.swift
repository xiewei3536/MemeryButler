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

            let (bytes, response) = try await URLSession.shared.bytes(from: url)
            let total = response.expectedContentLength
            var data = Data()
            if total > 0 { data.reserveCapacity(Int(total)) }
            var received: Int64 = 0
            for try await byte in bytes {
                data.append(byte)
                received += 1
                if total > 0, received % 131_072 == 0 {
                    status = .downloading(Double(received) / Double(total))
                }
            }
            try data.write(to: tmp)

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
        case toolFailed(tool: String, output: String)

        var errorDescription: String? {
            switch self {
            case .dmgMissingApp:
                return "DMG missing MemoryButler.app"
            case .toolFailed(let tool, let output):
                return "\(tool): \(String(output.suffix(120)))"
            }
        }
    }
}
