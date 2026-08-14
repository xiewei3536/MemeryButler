import SwiftUI
import AppKit

@main
struct MemoryButlerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// 選單列常駐標籤：晶片圖示 +（可選）即時使用率
struct MenuBarLabel: View {
    @ObservedObject private var monitor = AppModel.shared.monitor
    @ObservedObject private var settings = AppModel.shared.settings

    var body: some View {
        if settings.showPercentInMenuBar {
            HStack(spacing: 3) {
                Image(systemName: "memorychip")
                Text(Fmt.percent(monitor.current.usedFraction))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        } else {
            Image(systemName: "memorychip")
        }
    }
}
