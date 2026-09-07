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
        "auto.live": ["Pressure %@ · %@ available · %d checks", "压力%@ · 可用 %@ · 已检查 %d 次", "壓力%@ · 可用 %@ · 已檢查 %d 次"],
        "decision.lowpower":   ["Low Power Mode — auto-free paused", "低电量模式中，暂停自动释放", "低耗電模式中，暫停自動釋放"],
        "decision.cooling":    ["%@ (cooling down, ~%d min)", "%@（冷却中，约 %d 分钟后可再释放）", "%@（冷卻中，約 %d 分鐘後可再釋放）"],
        "decision.acting":     ["%@ → auto-freeing", "%@ → 自动释放", "%@ → 自動釋放"],
        "decision.reason.pressureSignal": ["Kernel sent a %@ pressure signal", "内核发出%@压力信号", "核心發出%@壓力訊號"],
        "decision.reason.pressure":  ["Memory pressure is %@", "内存压力%@", "記憶體壓力%@"],
        "decision.reason.threshold": ["Available only %d%%, sustained 30s", "可用内存仅 %d%%，已持续 30 秒", "可用記憶體僅 %d%%，已持續 30 秒"],
        "decision.reason.schedule":  ["%d-minute schedule reached", "已到 %d 分钟定时", "已達 %d 分鐘排程"],
        "decision.tooTight": ["System too busy to assist — will retry in 2 min", "系统正忙，2 分钟后再试", "系統正忙，2 分鐘後再試"],
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
        "hist.clear.confirm": ["Clear all? Click again", "确定清除？再点一次", "確定清除？再按一次"],
        "hist.note.swap":     ["stopped early to avoid swapping", "提前停止，避免写入磁盘", "提早停止，避免寫入磁碟"],
        "hist.note.critical": ["stopped early — critical pressure", "提前停止，压力临界", "提早停止，壓力緊繃"],
        "hist.note.thermal":  ["stopped early — Mac running hot", "提前停止，温度偏高", "提早停止，溫度偏高"],

        // App 分頁（誰在佔用記憶體）
        "tab.apps":        ["Apps", "应用", "App"],
        "apps.title":      ["Who's using memory", "谁在占用内存", "誰在佔用記憶體"],
        "apps.sub":        ["Helpers grouped under their app · same figures as Activity Monitor", "辅助进程已归入所属 App · 与「活动监视器」口径相同", "輔助程序已歸入所屬 App · 與「活動監視器」口徑相同"],
        "apps.scanning":   ["Scanning…", "正在扫描…", "正在掃描…"],
        "apps.processes":  ["%d processes", "%d 个进程", "%d 個程序"],
        "apps.other":      ["Background & system processes", "后台与系统进程", "背景與系統程序"],
        "apps.quit":       ["Quit", "退出", "結束"],
        "apps.confirmQuit": ["Quit now", "确定退出", "確定結束"],
        "apps.cancel":     ["Cancel", "取消", "取消"],
        "apps.quit.help":  ["Same as pressing ⌘Q in that app — it will ask before losing unsaved work", "相当于在该 App 中按 ⌘Q，未保存的内容会由它提示保存", "相當於在該 App 中按 ⌘Q，未儲存的內容會由它提示儲存"],
        "apps.self":       ["MemoryButler itself uses %@", "内存管家自身占用 %@", "記憶體管家自身佔用 %@"],

        // 白話健康判讀
        "insight.healthy":            ["Memory is comfortable — everything's smooth", "内存充足，运行顺畅", "記憶體充足，運作順暢"],
        "insight.compressing.title":  ["Memory is getting tight", "内存开始吃紧", "記憶體開始吃緊"],
        "insight.compressing.advice": ["macOS is compressing memory to keep up. Quitting idle apps helps the most.", "系统正靠压缩内存撑着，关闭闲置 App 最有帮助。", "系統正靠壓縮記憶體撐著，關閉閒置 App 最有幫助。"],
        "insight.swapping.title":     ["Out of memory — using the disk instead", "内存不足，已在用磁盘顶替", "記憶體不夠，已在用磁碟頂替"],
        "insight.swapping.advice":    ["This is why things feel slow. Quitting the biggest apps is the real fix — freeing can't help here.", "这就是变卡的原因。关掉最耗内存的 App 才是真正的解法，释放帮不上忙。", "這就是變卡的原因。關掉最耗記憶體的 App 才是真正的解法，釋放幫不上忙。"],
        "insight.critical.title":     ["Memory is critically low", "内存极度紧张", "記憶體極度緊繃"],
        "insight.critical.advice":    ["Quit a few apps right now.", "请立即关闭几个 App。", "請立即關閉幾個 App。"],
        "insight.seeApps":            ["See which apps", "看看是哪些 App", "看看是哪些 App"],

        // 自動決策（1.2 新增）
        "decision.thermal":     ["Mac is running hot — auto-free paused", "Mac 温度偏高，暂停自动释放", "Mac 溫度偏高，暫停自動釋放"],
        "decision.swapLimited": ["Freed %@ (cache only) — memory is truly full; quitting apps is what helps", "已释放 %@（仅缓存）——内存确实不够，关闭 App 才有效", "已釋放 %@（僅快取）——記憶體確實不夠，關閉 App 才有效"],

        // 懸停說明：把術語翻成白話
        "help.pressure":   ["macOS's own verdict on how tight memory is right now", "系统自己对当前内存紧张程度的判断", "系統自己對目前記憶體吃緊程度的判斷"],
        "help.available":  ["What apps can still grab right now, including cache that macOS would give up instantly", "App 现在还能立刻取用的内存，包含系统随时可让出的缓存", "App 現在還能立刻取用的記憶體，包含系統隨時可讓出的快取"],
        "help.swap":       ["Memory parked on disk. Large and growing means RAM ran out — that's what makes a Mac feel slow", "被搬到磁盘上的内存。数值大且持续增加 = 内存不够了，这正是变慢的原因", "被搬到磁碟上的記憶體。數值大且持續增加＝記憶體不夠了，這正是變慢的原因"],
        "help.app":        ["Memory used by apps and their windows", "App 及其窗口正在使用的内存", "App 及其視窗正在使用的記憶體"],
        "help.wired":      ["Reserved by macOS itself; can't be freed", "系统内核保留，无法释放", "系統核心保留，無法釋放"],
        "help.compressed": ["Idle memory macOS squeezed to make room; costs a little CPU to unpack when needed", "系统压缩起来腾空间的闲置内存，取用时需解压", "系統壓縮起來騰空間的閒置記憶體，取用時需稍微解壓"],
        "help.cached":     ["Recently used files kept in RAM for speed; handed back instantly when needed", "为加速而留在内存中的文件，需要时即刻让出", "為加速而留在記憶體中的檔案，需要時即刻讓出"],
        "help.release":    ["Nudges macOS to drop caches and compress idle apps. Stops the moment anything would be written to disk, and declines outright when it can't help.", "促使系统清掉缓存、压缩闲置 App；一旦要写入磁盘就自动停止，帮不上忙时会直接说明。", "促使系統清掉快取、壓縮閒置 App；一旦要寫入磁碟就自動停止，幫不上忙時會直接說明。"],
        "footer.quit.help": ["Quit MemoryButler (⌘Q)", "退出内存管家（⌘Q）", "結束記憶體管家（⌘Q）"],

        // 起跑前判定出手無益（按鈕短句 + 自動決策說明）
        "btn.skipped.compressorFull": ["Freeing won't help now — quit apps instead", "此刻释放无效，请改为关闭 App", "此刻釋放無效，請改關閉 App"],
        "btn.skipped.swapping":       ["Mac is swapping right now — not adding pressure", "系统正在写入磁盘，先不施压", "系統正在寫入磁碟，先不施壓"],
        "btn.skipped.critical":       ["Memory is critical — freeing would make it worse", "内存已临界，释放只会更糟", "記憶體已緊繃，釋放只會更糟"],
        "decision.skip.compressor": ["Freeing can't help now — it would only push apps to disk. Quitting apps is what helps.", "此刻释放帮不上忙，再施压只会把 App 写进磁盘；关闭 App 才有效", "此刻釋放幫不上忙，再施壓只會把 App 寫進磁碟；關閉 App 才有效"],
        "decision.skip.swapping":   ["Mac is swapping right now — the butler stays out of the way", "系统正在写入磁盘，管家不添乱", "系統正在寫入磁碟，管家不添亂"],
        "decision.skip.critical":   ["Pressure is critical — adding ballast would hurt; quit some apps", "压力已临界，此时施压只会更糟，请关闭几个 App", "壓力已緊繃，此時施壓只會更糟，請關閉幾個 App"],
        "hist.note.compressor":     ["stopped early — one compression pass is enough", "提前停止，压缩一轮即止", "提早停止，壓縮一輪即止"],
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
