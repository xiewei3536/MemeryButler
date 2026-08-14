import Foundation

// MARK: - 語言選項

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:             return L("lang.system")
        case .english:            return "English"
        case .simplifiedChinese:  return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }
}

// MARK: - 字串表（en / zh-Hans / zh-Hant）

enum L10n {
    static var language: AppLanguage = .system

    static var index: Int {
        switch language {
        case .english:            return 0
        case .simplifiedChinese:  return 1
        case .traditionalChinese: return 2
        case .system:
            for id in Locale.preferredLanguages {
                let l = id.lowercased()
                if l.hasPrefix("zh") {
                    if l.contains("hant") || l.contains("-tw") || l.contains("-hk") || l.contains("-mo") { return 2 }
                    return 1
                }
                if l.hasPrefix("en") { return 0 }
            }
            return 0
        }
    }

    static let table: [String: [String]] = [
        // 分頁與框架
        "app.name":        ["MemoryButler", "内存管家", "記憶體管家"],
        "tab.overview":    ["Overview", "总览", "總覽"],
        "tab.settings":    ["Settings", "设置", "設定"],
        "tab.history":     ["History", "记录", "紀錄"],
        "footer.quit":     ["Quit", "退出", "結束"],

        // 壓力
        "pressure.normal":   ["Good", "良好", "良好"],
        "pressure.warning":  ["Elevated", "偏高", "偏高"],
        "pressure.critical": ["Critical", "紧绷", "緊繃"],
        "chip.pressure":     ["Pressure: %@", "压力%@", "壓力%@"],

        // 總覽
        "gauge.used":     ["Used", "已使用", "已使用"],
        "sum.available":  ["Available", "可用", "可用"],
        "sum.total":      ["Total", "总量", "總量"],
        "sum.swap":       ["Swap", "交换空间", "交換空間"],
        "tile.app":       ["App Memory", "App 内存", "App 記憶體"],
        "tile.wired":     ["Wired", "联动内存", "已固定"],
        "tile.compressed": ["Compressed", "已压缩", "已壓縮"],
        "tile.cached":    ["Cached Files", "缓存文件", "快取檔案"],
        "chart.title":    ["Memory Usage · Last 5 min", "内存使用率 · 最近 5 分钟", "記憶體使用率 · 最近 5 分鐘"],
        "btn.release":    ["Free Memory Now", "立即释放内存", "立即釋放記憶體"],
        "btn.releasing":  ["Freeing…", "正在释放…", "正在釋放…"],
        "btn.freed":      ["Freed %@", "已释放 %@", "已釋放 %@"],
        "btn.tidied":     ["All Tidied Up", "已完成整理", "已完成整理"],
        "auto.on":        ["Smart Auto-Free is On", "智能自动释放已开启", "智慧自動釋放已開啟"],
        "auto.off":       ["Smart Auto-Free is Off", "智能自动释放已关闭", "智慧自動釋放已關閉"],
        "auto.hint.off":  ["Enable it in the Settings tab", "到「设置」页即可开启", "到「設定」分頁即可開啟"],
        "auto.cooldown":  ["Cooldown %@", "冷却 %@", "冷卻 %@"],

        // 自動決策
        "decision.monitoring": ["Monitoring", "监控中", "監控中"],
        "decision.lowpower":   ["Low Power Mode — auto-free paused", "低电量模式中，暂停自动释放", "低耗電模式中，暫停自動釋放"],
        "decision.cooling":    ["%@ (cooling down, ~%d min)", "%@（冷却中，约 %d 分钟后可再释放）", "%@（冷卻中，約 %d 分鐘後可再釋放）"],
        "decision.acting":     ["%@ → auto-freeing", "%@ → 自动释放", "%@ → 自動釋放"],
        "decision.reason.pressureSignal": ["Kernel sent a %@ pressure signal", "内核发出%@压力信号", "核心發出%@壓力訊號"],
        "decision.reason.pressure":  ["Memory pressure is %@", "内存压力%@", "記憶體壓力%@"],
        "decision.reason.threshold": ["Available only %d%%, sustained 30s", "可用内存仅 %d%%，已持续 30 秒", "可用記憶體僅 %d%%，已持續 30 秒"],
        "decision.reason.schedule":  ["%d-minute schedule reached", "已到 %d 分钟定时", "已達 %d 分鐘排程"],
        "decision.limited": ["Limited effect (%@), backing off", "收效有限（%@），拉长冷却避免空转", "成效有限（%@），拉長冷卻避免空轉"],
        "decision.freed":   ["Freed %@", "已释放 %@", "已釋放 %@"],

        // 觸發來源
        "trigger.manual":    ["Manual", "手动释放", "手動釋放"],
        "trigger.pressure":  ["Pressure Alert", "压力警告", "壓力警告"],
        "trigger.threshold": ["Low Available", "可用偏低", "可用偏低"],
        "trigger.schedule":  ["Scheduled", "定时计划", "定時排程"],

        // 設定
        "set.auto.title":      ["Smart Auto-Free", "智能自动释放", "智慧自動釋放"],
        "set.auto.sub":        ["The butler monitors and acts at the right moment", "由管家自主监控并在适当时机释放", "由管家自主監控並在適當時機釋放"],
        "set.pressure.title":  ["Free on pressure alert", "压力警告时释放", "壓力警告時釋放"],
        "set.pressure.sub":    ["Act the moment the kernel signals", "收到系统内核压力信号立即行动", "收到系統核心壓力訊號立即行動"],
        "set.threshold.title": ["Free when available is low", "可用内存过低时释放", "可用記憶體過低時釋放"],
        "set.threshold.sub":   ["Below %d%% for 30 seconds", "低于 %d%% 并持续 30 秒", "低於 %d%% 並持續 30 秒"],
        "set.schedule.title":  ["Scheduled free", "定时释放", "定時釋放"],
        "set.schedule.sub.on":  ["Tidy up every %d minutes", "每 %d 分钟整理一次", "每 %d 分鐘整理一次"],
        "set.schedule.sub.off": ["Tidy on a fixed rhythm", "以固定节奏定期整理", "以固定節奏定期整理"],
        "sched.15":  ["Every 15 min", "每 15 分钟", "每 15 分鐘"],
        "sched.30":  ["Every 30 min", "每 30 分钟", "每 30 分鐘"],
        "sched.60":  ["Every hour", "每 60 分钟", "每 60 分鐘"],
        "sched.120": ["Every 2 hours", "每 2 小时", "每 2 小時"],
        "set.cooldown.title": ["Cooldown", "冷却时间", "冷卻時間"],
        "set.cooldown.sub":   ["At least %d min between auto-frees; doubles when gains are small", "两次自动释放至少间隔 %d 分钟，收效不佳时自动加倍", "兩次自動釋放至少間隔 %d 分鐘，成效不佳時自動加倍"],
        "set.lowpower.title": ["Pause in Low Power Mode", "低电量模式时暂停", "低耗電模式時暫停"],
        "set.lowpower.sub":   ["No auto-free while saving battery", "省电期间不执行自动释放", "省電期間不執行自動釋放"],
        "set.menubar.title":  ["Show usage in menu bar", "菜单栏显示使用率", "選單列顯示使用率"],
        "set.login.title":    ["Launch at login", "登录时自动启动", "登入時自動啟動"],
        "set.login.sub":      ["Quietly on duty after boot", "开机后静静守在菜单栏", "開機後靜靜守在選單列"],
        "set.lang.title":     ["Language", "语言", "語言"],
        "lang.system":        ["System", "跟随系统", "跟隨系統"],

        // 軟體更新
        "set.update.title":   ["Software Update", "软件更新", "軟體更新"],
        "set.update.current": ["Current version %@", "当前版本 %@", "目前版本 %@"],
        "set.update.auto":    ["Check for updates automatically", "自动检查更新", "自動檢查更新"],
        "set.update.check":   ["Check Now", "立即检查", "立即檢查"],
        "update.checking":    ["Checking…", "检查中…", "檢查中…"],
        "update.uptodate":    ["You're up to date", "已是最新版本", "已是最新版本"],
        "update.failed":      ["Update failed: %@", "更新失败：%@", "更新失敗：%@"],
        "update.banner.title": ["Version %@ is available", "新版本 %@ 已推出", "新版本 %@ 已推出"],
        "update.banner.button": ["Update Now", "立即更新", "立即更新"],
        "update.downloading": ["Downloading %d%%", "下载中 %d%%", "下載中 %d%%"],
        "update.installing":  ["Installing…", "安装中…", "安裝中…"],
        "update.restarting":  ["Installed — restarting", "已安装，即将重启", "已安裝，即將重新啟動"],
        "update.notif.title": ["MemoryButler update available", "内存管家有新版本", "記憶體管家有新版本"],
        "update.notif.body":  ["Version %@ is out. Open the menu bar panel to update in one click.", "新版本 %@ 已发布，打开菜单栏面板即可一键更新。", "新版本 %@ 已發布，打開選單列面板即可一鍵更新。"],
        "update.dev":         ["Updates require the installed .app", "开发模式下无法自动更新", "開發模式下無法自動更新"],

        // 關於
        "about.opensource":  ["Free & open-source software under the MIT License", "基于 MIT 许可证的自由开源软件", "基於 MIT 授權的自由開源軟體"],
        "about.viewSource":  ["Source Code", "查看源码", "查看原始碼"],
        "about.reportIssue": ["Report an Issue", "反馈问题", "回報問題"],
        "about.releases":    ["All Releases", "全部版本", "全部版本"],

        // 紀錄
        "hist.empty.title": ["No releases yet", "还没有释放记录", "還沒有釋放紀錄"],
        "hist.empty.sub":   ["Free manually or let the butler act —\nevery tidy-up will be logged here.", "手动释放或等管家自动出手后，\n每一次整理都会记在这里。", "手動釋放或等管家自動出手後，\n每一次整理都會記在這裡。"],
        "hist.total":       ["Total Freed", "累计释放", "累計釋放"],
        "hist.count":       ["Times", "次数", "次數"],
        "hist.clear":       ["Clear History", "清除记录", "清除紀錄"],
    ]
}

/// 取得目前語言的字串
func L(_ key: String) -> String {
    guard let row = L10n.table[key], row.count == 3 else { return key }
    return row[L10n.index]
}

/// 取得並格式化
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
