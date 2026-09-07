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
- 🛑 **不再可能幫倒忙**——8GB 機器實測：1.1.3「釋放 1.9GB」其實是把 1.8GB *其他 App* 寫進磁碟，之後切回反而更卡。1.2.0 一旦交換空間成長或壓縮池漸滿就立刻停止，且在壓縮池已佈 RAM 12% 以上、swap 正在成長或壓力緊繃時**直接拒絕出手並說明原因**。實測釋放後 swap 成長從 +1.8GB 降為 0。
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
