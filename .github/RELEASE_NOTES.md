## What's new in 1.4.1

**English** — Fix: on smaller or HiDPI-scaled screens (e.g. a monitor running "looks like 1280×720") the panel was taller than the screen and its bottom was cut off. The panel now sizes itself to the screen it opens on and scrolls only when the content doesn't fit, and each tab remembers its height so switching tabs doesn't jump. The Overview now puts the verdict and actions first and the chart last, and is tightened so the everyday case fits a 720-point-tall screen without scrolling. The gauge ring is no longer clipped at the edge, Apps rows are slightly tighter so nine apps fit, and History's Clear button moved into the summary card. The self-test now reports each tab's natural height against the screen (`MEMORYBUTLER_SNAPSHOT_SCREEN_HEIGHT` simulates other screens).

**简体中文** — 修复：在较小或 HiDPI 缩放的屏幕上（例如「看起来像 1280×720」），面板比屏幕还高，底部被切掉。现在面板会依所在屏幕自动限制高度，内容放不下时才滚动，各分页记住自己的高度，切换时不会跳动。总览改为判断与操作在前、曲线在最后，并更紧凑，720 点高的屏幕在日常情况下不必滚动即可完整显示。仪表环不再被裁切，「应用」页每行更紧凑（9 个 App 放得下），「记录」页的清除按钮移到摘要卡片里。自我测试会报告各分页的自然高度与屏幕上限（`MEMORYBUTLER_SNAPSHOT_SCREEN_HEIGHT` 可模拟其他屏幕）。

**繁體中文** — 修正：在較小或 HiDPI 縮放的螢幕上（例如「看起來像 1280×720」），面板比螢幕還高，底部被切掉。現在面板會依所在螢幕自動限制高度，內容放不下時才捲動，各分頁記住自己的高度，切換時不會跳動。總覽改為判斷與動作在前、曲線在最後，並更精簡，720 點高的螢幕在日常情況下不必捲動即可完整顯示。儀表環不再被裁切，「App」分頁每列更緊湊（9 個 App 放得下），「紀錄」分頁的清除按鈕移到摘要卡片裡。自我測試會回報各分頁的自然高度與螢幕上限（`MEMORYBUTLER_SNAPSHOT_SCREEN_HEIGHT` 可模擬其他螢幕）。

---

## What's new in 1.4.0 — smoothness first

**English**
- 🐢 **Lag detection** — finds what is actually making your Mac slow and says it in one line: apps hogging the CPU (e.g. a stuck sync client at 90% for an hour), memory being read back from disk *right now* (MB/s), CPU heat throttling, a high-refresh external display on Intel graphics, days of uptime with gigabytes of swap. The header shows one verdict — Smooth / A bit slow / Laggy.
- 🛠 **One-click fixes** — for a runaway app: **Lower priority** (no root, reversible, restored automatically when you switch to that app), **Restart** (the real cure for a stuck sync client) or **Quit**. Menu-bar apps and Apple's background workers (Spotlight indexing, Siri Suggestions, Photos analysis) that hog the CPU for 5 minutes are calmed automatically and handed back their priority as soon as they go idle — never apps in the Dock, Apple's UI, calls, remote desktop, recorders or VPNs. Calmed items stay listed with a Restore button, and nothing is left calmed after MemoryButler quits, even after a crash. You get a notification after 10 minutes.
- 🛑 **Freeing never wastes effort** — measured on an 8GB Mac with 3GB of swap: the hourly scheduled release reclaimed 0MB in 60 of 60 runs while pushing 1GB+ of other apps into compression 30 times, i.e. a stutter every hour. Freeing now declines whenever swap is ≥ ¼ of RAM or the Mac is swapping right now; after 3 runs that reclaim nothing, auto-free pauses for 6 hours; scheduled runs skip when memory is plentiful. History shows how many runs were actually effective.
- 🪶 **Lighter** — idle CPU 1.2% → 0.36%: the hidden panel no longer redraws its chart every 2 seconds, and the menu bar redraws only when the number changes.
- ✨ **Redesigned** — icon tab bar, smoothness chip, a compact stats strip, swap rate next to swap size, refined buttons, Settings in sections. Fix: uptime now includes sleep (it showed 1 day on a Mac up for 7).
- 🧪 For developers: `MEMORYBUTLER_SELFTEST=checks` runs 533 logic checks (thresholds, refusal rules, futility learning, runaway hysteresis, translation format strings) in CI; the self-test no longer runs a release unless `MEMORYBUTLER_SELFTEST_RELEASE=1`.

**简体中文**
- 🐢 **卡顿侦测**——找出真正让 Mac 变慢的原因，一句话说清楚：占满 CPU 的程序（例如卡住的同步程序连续一小时 90%）、此刻正从磁盘读回内存（MB/s）、CPU 过热降速、Intel 内显接高刷新率外接屏幕、连续开机多天且交换空间好几 GB。标题栏直接显示一个判断：顺畅／有点卡／很卡。
- 🛠 **一键处理**——失控的程序可以**降到后台**（免 root、可还原，切换到该 App 时自动恢复）、**重新启动**（同步程序卡住时真正有效）或**退出**。菜单栏程序与 Apple 的后台工作进程（Spotlight 索引、Siri 建议、照片分析）连续 5 分钟占满 CPU 会被自动压制，一闲下来就自动恢复——绝不碰 Dock 上的 App、系统界面、通话、远程桌面、录屏与 VPN。被压制的项目会一直列着并附「恢复」按钮，内存管家退出（甚至崩溃）后也不会留下被压着的程序。10 分钟后还会通知你。
- 🛑 **释放不再白费力气**——8GB、交换空间 3GB 的 Mac 实测：每小时定时释放 60 次全部回收 0MB，其中 30 次把 1GB 以上的其他 App 挤进压缩，等于每小时卡一下。现在交换空间达内存 ¼ 或正在换页时一律不出手；连续 3 次没效果就暂停自动释放 6 小时；内存充足时跳过定时释放。记录页显示真正有效的次数。
- 🪶 **更轻**——闲置 CPU 1.2% → 0.36%：面板关着时不再每 2 秒重画曲线，菜单栏只在数字变化时重画。
- ✨ **重新设计**——图标分页栏、顺畅度徽章、紧凑的四项细目、交换空间旁显示换入速率、更精致的按钮、设置分区。修复：开机时长改为包含睡眠时间（原本开机 7 天只显示 1 天）。
- 🧪 开发者：`MEMORYBUTLER_SELFTEST=checks` 在 CI 中执行 533 项逻辑检查（门槛、拒绝出手条件、无效学习、失控迟滞、三语格式字符串）；自我测试默认不再执行释放（需 `MEMORYBUTLER_SELFTEST_RELEASE=1`）。

**繁體中文**
- 🐢 **卡頓偵測**——找出真正讓 Mac 變慢的原因，一句話講清楚：佔滿 CPU 的程式（例如卡住的同步程式連續一小時 90%）、此刻正從磁碟讀回記憶體（MB/s）、CPU 過熱降速、Intel 內顯接高更新率外接螢幕、連續開機多天且交換空間好幾 GB。標題列直接顯示一個判斷：順暢／有點卡／很卡。
- 🛠 **一鍵處理**——失控的程式可以**降到背景**（免 root、可還原，切換到該 App 時自動恢復）、**重新啟動**（同步程式卡住時真正有效）或**結束**。選單列程式與 Apple 的背景工作程序（Spotlight 索引、Siri 建議、照片分析）連續 5 分鐘佔滿 CPU 會被自動壓制，一閒下來就自動恢復——絕不碰 Dock 上的 App、系統介面、通話、遠端桌面、錄影與 VPN。被壓制的項目會一直列著並附「恢復」按鈕，記憶體管家結束（甚至當機）後也不會留下被壓著的程式。10 分鐘後還會通知你。
- 🛑 **釋放不再白費力氣**——8GB、交換空間 3GB 的 Mac 實測：每小時定時釋放 60 次全部回收 0MB，其中 30 次把 1GB 以上的其他 App 擠進壓縮，等於每小時卡一下。現在交換空間達記憶體 ¼ 或正在換頁時一律不出手；連續 3 次沒效果就暫停自動釋放 6 小時；記憶體充足時略過定時釋放。紀錄分頁顯示真正有效的次數。
- 🪶 **更輕**——閒置 CPU 1.2% → 0.36%：面板關著時不再每 2 秒重畫曲線，選單列只在數字變化時重畫。
- ✨ **重新設計**——圖示分頁列、順暢度徽章、精簡的四項細目、交換空間旁顯示換入速率、更精緻的按鈕、設定分區。修正：開機時長改為包含睡眠時間（原本開機 7 天只顯示 1 天）。
- 🧪 開發者：`MEMORYBUTLER_SELFTEST=checks` 在 CI 執行 533 項邏輯檢查（門檻、拒絕出手條件、無效學習、失控遲滯、三語格式字串）；自我測試預設不再執行釋放（需 `MEMORYBUTLER_SELFTEST_RELEASE=1`）。

---

## What's new in 1.3.1

**English** — Visual polish pass. Apps tab: bars were scaled against the first row, so after sorting by CPU the bars of bigger apps overflowed their cards; they now scale against the largest row and never exceed 100%. Sorting by CPU now makes CPU the headline figure and the bar (indigo), with memory in the secondary line; the title follows the sort. Header no longer truncates. Apple system components: Finder-class apps are listed without a Quit button, menu-bar-only system helpers fold into "Background & system processes". System tab: even tile heights (battery cycles moved to the info card). Overview chip now reads "Memory pressure", Activity Monitor's term, so it no longer seems to contradict the butler's verdict. Verified in light and dark mode.

**简体中文** — 界面精致化。「应用」页：比例条原以第一行为分母，按 CPU 排序后内存更大的 App 会溢出卡片；现改以最大值为分母且不超过 100%。按 CPU 排序时主数字与比例条都改为 CPU（靛蓝），内存放副行，标题随排序变化；标题栏不再截断。系统组件：Finder 这类不再显示退出按钮，仅在菜单栏的系统小组件并入「后台与系统进程」。「系统」页六格高度一致（电池循环移到信息卡）。总览徽章改用活动监视器的用语「内存压力」，不再与判读看似矛盾。已在浅色与深色模式验证。

**繁體中文** — 介面精緻化。「App」分頁：比例條原以第一列為分母，依 CPU 排序後記憶體更大的 App 會溢出卡片；現改以最大值為分母且不超過 100%。依 CPU 排序時主數字與比例條都改為 CPU（靛藍），記憶體放副行，標題隨排序變化；標題列不再截斷。系統元件：Finder 這類不再顯示結束鈕，僅在選單列的系統小元件併入「背景與系統程序」。「系統」分頁六格高度一致（電池循環移到資訊卡）。總覽徽章改用活動監視器的用語「記憶體壓力」，不再與判讀看似矛盾。已在淺色與深色模式驗證。

---

## What's new in 1.3.0

**English**
- 🌡 **System tab** — CPU usage, CPU temperature, CPU and whole-Mac power (SMC sensors, no root), fan speed, thermal throttling level and current speed limit, battery health and cycles, display resolution/refresh rate, uptime, and how many third-party background services start at login (with a jump to Login Items). A plain-language verdict tells you when the Mac is slow because it is *hot*, which on old MacBooks is at least as common as memory.
- 🔥 **Apps tab shows CPU** — each app now shows its CPU use since the last refresh; sort by memory or by CPU to catch runaway apps.
- 💡 Flags external displays above 60Hz on Intel graphics: dropping to 60Hz is smoother and cooler.

**简体中文**
- 🌡 **「系统」页**——CPU 使用率、CPU 温度、CPU 与整机功耗（SMC 传感器，免 root）、风扇转速、热降频等级与当前速度限制、电池健康与循环次数、显示器分辨率/刷新率、开机时长、开机常驻的第三方后台服务数量（可一键跳到登录项）。白话判读会告诉你 Mac 变慢是不是因为「热」——老 MacBook 上这至少和内存一样常见。
- 🔥 **「应用」页显示 CPU**——每个 App 显示自上次刷新以来的 CPU 用量，可按内存或 CPU 排序，抓出失控的 App。
- 💡 Intel 内显接高刷新率外接屏幕时提示：改 60Hz 更顺也更凉。

**繁體中文**
- 🌡 **「系統」分頁**——CPU 使用率、CPU 溫度、CPU 與整機功耗（SMC 感測器，免 root）、風扇轉速、熱降頻等級與目前速度限制、電池健康與循環次數、螢幕解析度／更新率、開機時長、開機常駐的第三方背景服務數量（可一鍵跳到登入項目）。白話判讀會告訴你 Mac 變慢是不是因為「熱」——老 MacBook 上這至少和記憶體一樣常見。
- 🔥 **「App」分頁顯示 CPU**——每個 App 顯示自上次刷新以來的 CPU 用量，可依記憶體或 CPU 排序，抓出失控的 App。
- 💡 Intel 內顯接高更新率外接螢幕時提示：改 60Hz 更順也更涼。

---

## What's new in 1.2.2

**English** — Fix: MemoryButler kept burning 12–19% CPU with its panel closed. The panel's views stay alive after it closes, so the pulsing "supervision" dot (a repeat-forever animation, present since 1.1.3) and the gauge transition kept re-laying out at the display refresh rate — 144 times a second on a high-refresh monitor. Animations and timers now pause whenever the panel is not visible, and the pulse runs at 12 fps when it is. Idle CPU is now ~0%.

**简体中文** — 修复：面板关着时内存管家仍占用 12–19% CPU。面板关闭后其视图仍然存活，「监督中」的呼吸灯（1.1.3 起的 repeat-forever 动画）和仪表环过场动画会按屏幕刷新率持续重排版，在高刷屏上每秒 144 次。现在面板不可见时所有动画与计时器暂停，可见时呼吸灯以 12 fps 运行，空闲 CPU 约为 0%。

**繁體中文** — 修正：面板關著時記憶體管家仍佔用 12～19% CPU。面板關閉後其視圖仍然活著，「監督中」的呼吸燈（1.1.3 起的 repeat-forever 動畫）與儀表環過場動畫會依螢幕更新率持續重排版，高更新率螢幕上每秒 144 次。現在面板不可見時所有動畫與計時器暫停，可見時呼吸燈以 12 fps 運行，閒置 CPU 約為 0%。

---

## What's new in 1.2.1

**English** — Fix: the Apps and History tabs collapsed to a single row (ScrollView inside a self-sizing menu bar panel). The panel now adapts to its content: the Apps list and short histories expand fully, long histories scroll at a fixed height, and Settings is as tall as Overview. Shorter "stopped early" notes in History so they no longer truncate.

**简体中文** — 修复：「应用」与「记录」页被压扁到只剩一行（自适应大小的菜单栏面板里放 ScrollView 的问题）。面板现在跟随内容自适应：应用列表与较短的记录完整展开，记录过多时才固定高度滚动，设置页与总览同高。记录里的「提前停止」注记缩短，不再被截断。

**繁體中文** — 修正：「App」與「紀錄」分頁被壓扁到只剩一列（自動調整大小的選單列面板裡放 ScrollView 的問題）。面板現在跟著內容自適應：App 列表與較短的紀錄完整展開，紀錄過多才固定高度捲動，設定分頁與總覽同高。紀錄裡的「提早停止」註記縮短，不再被截斷。

---

## What's new in 1.2.0

**English**
- 🛑 **Never harmful anymore** — on an 8GB Mac that was already swapping, 1.1.3 "freed 1.9GB" by pushing 1.8GB of *other apps* to disk, which made switching back to them slower. 1.2.0 stops the instant swap grows or the compressor fills, and **declines outright** (telling you why) when the compressor already holds >12% of RAM, swap is growing, or pressure is critical. Measured: swap growth after a release went from +1.8GB to 0.
- 🔍 **Apps tab** — see which apps use the most memory (helpers grouped under their app, same figures as Activity Monitor) and quit them gracefully in two clicks. On 8GB, this is the fix that actually works.
- 🩺 **Plain-language verdict** — one line under the gauge tells you whether the Mac is smooth, compressing, or already living on disk, and what to do about it. Hover any figure for an explanation.
- ⚡ **Lighter release** — ballast is filled ~9× faster (page-template copy instead of per-byte random), auto releases run at background priority, and auto-free pauses when the Mac is running hot.
- 🔄 **Update download** no longer stalls the panel; versions are derived from the release tag so the updater can't loop.
- ♿ Accessible switch labels, monospaced digits (no jitter in the menu bar), ⌘Q to quit, two-step confirmations.

**简体中文**
- 🛑 **不再可能帮倒忙**——8GB 机器实测：1.1.3 「释放 1.9GB」其实是把 1.8GB *其他 App* 写进了磁盘，之后切回反而更慢。1.2.0 一旦交换空间增长或压缩池渐满立即停止，且在压缩池已占 RAM 12% 以上、swap 正在增长或压力临界时**直接拒绝出手并说明原因**。实测释放后 swap 增长从 +1.8GB 降为 0。
- 🔍 **「应用」页**——看看谁占用内存最多（辅助进程归入所属 App，与活动监视器口径相同），两次点击温和退出。8GB 上这才是真正有效的解法。
- 🩺 **白话判读**——仪表下方一句话告诉你现在顺不顺、该做什么；悬停任何数字都有解释。
- ⚡ **更轻的释放**——压载填充快约 9 倍，自动释放改为后台优先级，机器过热时暂停。
- 🔄 更新下载不再卡面板；版本号由 release tag 推导，不会再无限提示更新。
- ♿ 开关带无障碍标签、等宽数字、⌘Q 退出、两段式确认。

**繁體中文**
- 🛑 **不再可能幫倒忙**——8GB 機器實測：1.1.3「釋放 1.9GB」其實是把 1.8GB *其他 App* 寫進磁碟，之後切回反而更卡。1.2.0 一旦交換空間成長或壓縮池漸滿就立刻停止，且在壓縮池已佔 RAM 12% 以上、swap 正在成長或壓力緊繃時**直接拒絕出手並說明原因**。實測釋放後 swap 成長從 +1.8GB 降為 0。
- 🔍 **「App」分頁**——看看誰佔用記憶體最多（輔助程序歸入所屬 App，與活動監視器口徑相同），兩下點擊溫和結束。8GB 上這才是真正有效的解法。
- 🩺 **白話判讀**——儀表下方一句話告訴你現在順不順、該做什麼；懸停任何數字都有說明。
- ⚡ **更輕的釋放**——壓載填充快約 9 倍，自動釋放改為背景優先權，機器過熱時暫停。
- 🔄 更新下載不再卡面板；版本號由 release tag 推導，不會再無限提示更新。
- ♿ 開關帶無障礙標籤、等寬數字、⌘Q 結束、兩段式確認。

---

## MemoryButler

**English** — A smart memory butler for low-RAM Macs. Monitors memory pressure in real time and frees memory autonomously (kernel-pressure / low-threshold / schedule triggers, adaptive cooldown). Multilingual UI (EN / 简体 / 繁體) with built-in one-click auto-update. Universal Binary for Intel & Apple Silicon, macOS 13+.

📥 Download `MemoryButler.dmg` below, drag into Applications, then **right-click → Open** on first launch.

---

**简体中文** — 为小内存 Mac 而生的智能内存管家。实时监控内存压力，自主释放内存（内核压力 / 低阈值 / 定时三重触发，自适应冷却）。多语言界面（英/简/繁），内置一键自动更新。Universal Binary 同时支持 Intel 与 Apple Silicon，需 macOS 13+。

📥 在下方下载 `MemoryButler.dmg`，拖入「应用程序」，首次启动请**右键 → 打开**。

---

**繁體中文** — 為小記憶體 Mac 而生的智慧記憶體管家。即時監控記憶體壓力,自主釋放記憶體(核心壓力 / 低門檻 / 定時三重觸發,自適應冷卻)。多語言介面(英/簡/繁),內建一鍵自動更新。Universal Binary 同時支援 Intel 與 Apple Silicon,需 macOS 13+。

📥 在下方下載 `MemoryButler.dmg`,拖進「應用程式」,首次啟動請**按右鍵 → 打開**。
