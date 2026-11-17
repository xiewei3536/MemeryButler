# 開發、驗證與發版

## 1. 建置與回歸檢查

需求：macOS 13+、Swift 5.9+、Xcode Command Line Tools。無第三方套件。

```bash
./scripts/verify.sh
```

腳本限制兩個編譯工作（可用 `JOBS` 調整）、將編譯警告視為錯誤，再執行 844 項檢查。涵蓋釋放守門、無效退避、CPU 身分／差額、前景保護、睡眠空窗、熱判讀、三語字串、更新來源／雜湊／App 身分。實際優先權測試只建立及操作自己的 `sleep` 子程序。Mach port 測試連續讀取記憶體／CPU，確認 send-right 引用不增加。

CI 固定使用仍受支援的 `macos-15`（Apple Silicon）及 `macos-15-intel`，各自執行原生建置、844 項檢查與小螢幕快照；Release 亦使用 macOS 15。macOS 14 runner 已於 2026-11-02 退役，不再使用。

## 2. 三語、深淺色、小螢幕

```bash
./scripts/verify.sh --snapshots
```

產生英文、簡體中文、繁體中文 × 淺色／深色共六組，每組九張 PNG。輸出路徑由 `mktemp` 產生，會印在最後；每組 `run.log` 保留即時診斷及分頁高度。螢幕可用高度模擬為 695pt。任一分頁超高、渲染／寫檔失敗，腳本必須回傳非零。離屏控制項使用靜態替代，不改變正式 App 的原生開關。

自我測試不啟動自動釋放、降級、通知、更新檢查或當機降級清單還原，也不改寫自動釋放的正式狀態。診斷讀值來自當下機器；示範卡片不是實測失控證據。只有額外明確設定 `MEMORYBUTLER_SELFTEST_RELEASE=1`，才會實際嘗試一次釋放；一般驗證與 CI 均不設定。

可單獨執行：

```bash
MEMORYBUTLER_SELFTEST=1 \
MEMORYBUTLER_SNAPSHOT_DIR=/tmp/memorybutler-shots \
MEMORYBUTLER_SNAPSHOT_LANGUAGE=zh-Hant \
MEMORYBUTLER_SNAPSHOT_SCREEN_HEIGHT=695 \
.build/debug/MemoryButler
```

## 3. 取樣與保護原則

| 狀態 | 記憶體取樣 | 程序掃描 |
| --- | --- | --- |
| 面板開啟 | 2 秒 | 10 秒 |
| 面板隱藏 | 6 秒 | 15 秒 |
| 低耗電、面板開啟 | 4 秒 | 30 秒 |
| 低耗電、面板隱藏 | 10 秒 | 30 秒 |
| 記憶體警告／緊繃 | 2 秒，另有即時核心事件 | 依面板／低耗電狀態 |
| 系統睡眠 | 停止 | 停止，還原已降級程序 |

- 以上是**取樣次數減少**，不是整台電腦效能提高的百分比。系統壓力大時刻意保留即時反應。
- 前景及最近 120 秒使用過的 App 不自動降級；一般 Dock App、系統介面、已辨識的即時通訊／遠端／錄影／VPN 與未知第三方獨立程序不自動處理。安全名單是啟發式，可能無法辨識所有即時服務；可在設定關閉自動降級。
- 自動操作不關閉或重啟 App、不刪除檔案、不更改顯示器、登入項目或系統效能設定。
- 優先權降低是暫時的競爭緩解，不會釋放該 App 的記憶體；8GB 工作集超量時無法靠清理工具保證順暢。
- `machdep.xcpm.cpu_thermal_level` 僅保留為診斷原始值，沒有假定的 0～100% 熱壓力刻度。介面根據 CPU 速度限制與公開的 `ProcessInfo.thermalState` 顯示效能限制。

## 4. Universal 發版

```bash
VERSION=1.5.0 ./build.sh
MEMORYBUTLER_SELFTEST=checks dist/MemoryButler.app/Contents/MacOS/MemoryButler
lipo -verify_arch x86_64 arm64 dist/MemoryButler.app/Contents/MacOS/MemoryButler
codesign --verify --deep --strict dist/MemoryButler.app
```

發版前更新三語 README、`.github/RELEASE_NOTES.md` 及 `build.sh` 預設版號。先推送 `main` 並確認 CI，再建立及推送正式 tag（例如 `v1.5.0`）。Release workflow 從同一個 tag 建置 Universal App／DMG、驗證版號、架構、簽章與邏輯檢查後發布。手動執行 workflow 時必須提供既有正式 tag，不能用 `main` 冒充版本。

更新程式只接受此專案 GitHub 的正式 Release 資產，檢查 HTTP、大小及 GitHub 有提供時的 SHA-256。先在同磁碟複製完成，確認 Bundle ID、預期版本、可執行檔與 codesign 驗證成功，再進行備份及重新命名；失敗嘗試還原，還原若失敗會保留備份。這不等於發行者身分公證：目前 App 為 ad-hoc 簽章，尚未使用 Developer ID／notarization。
