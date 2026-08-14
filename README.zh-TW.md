<div align="center">

<img src="docs/icon.png" width="128" alt="記憶體管家圖示">

# 記憶體管家 MemoryButler

**為小記憶體 Mac 而生的智慧管家——自主監控、自主決策、自主釋放，讓 8GB 的 Mac 也能順暢運作。**

[English](README.md) | [简体中文](README.zh-CN.md) | **繁體中文**

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Architecture](https://img.shields.io/badge/Intel%20%7C%20Apple%20Silicon-Universal-8A2BE2)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
[![Release](https://img.shields.io/github/v/release/xiewei3536/MemeryButler)](https://github.com/xiewei3536/MemeryButler/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## 為什麼需要它

8GB 記憶體的 Mac 常常在交換空間和壓縮記憶體之間掙扎,整台機器越用越卡。記憶體管家是一個極輕量的原生選單列 App,即時監控記憶體壓力,**在對的時機自動出手釋放記憶體**——不用點按、不用 root 密碼、不是臃腫的 Electron(它自己常駐僅約 35MB)。

## 功能特色

- 🧠 **智慧自主釋放**,三重觸發、全部可調:
  1. **核心壓力訊號**——macOS 回報記憶體壓力的瞬間立即反應
  2. **可用門檻**——可用記憶體低於 12%(可調)並持續 30 秒
  3. **定時排程**——每 15 分鐘到 2 小時,喜歡固定節奏也可以
- 📈 **自適應冷卻**——釋放成效差(系統真的很忙)就自動加倍退避,不做無效空轉;成效好則恢復正常節奏
- 🔋 **貼心守門**——低耗電模式自動暫停、壓力緊繃立即煞車、保留 300MB 安全水位
- 🎛 **精緻原生介面**——壓力儀表環、App/固定/壓縮/快取四格統計、最近 5 分鐘即時曲線(懸停讀值)、完整釋放紀錄
- 📊 **選單列一目瞭然**——使用率百分比直接顯示在選單列
- 🚀 **Universal Binary**——一個 App 同時支援 Intel 與 Apple Silicon,支援登入時自動啟動

## 安裝

1. 到[最新版本](https://github.com/xiewei3536/MemeryButler/releases/latest)下載 `MemoryButler.dmg`
2. 打開後把 **MemoryButler** 拖進「**應用程式**」
3. 第一次啟動:**在 App 上按右鍵 → 打開**(ad-hoc 簽名,Gatekeeper 只會問這一次)
4. 看選單列上的晶片圖示——你的管家已就位

## 運作原理

記憶體管家以受控速度向核心索取大量匿名記憶體並觸碰每一頁,迫使 XNU 立即回收閒置頁面、壓縮不活躍的 App、丟棄可清除快取,隨後一次性歸還,系統便多出大量真正可用的記憶體。全程免 root,並有硬性安全機制:可用水位保底、壓力煞車、總量與時間上限。

## 從原始碼建置

```bash
git clone https://github.com/xiewei3536/MemeryButler.git
cd MemeryButler
./build.sh   # 產出 dist/MemoryButler.app 與 dist/MemoryButler.dmg
```

需求:macOS 13+、Xcode Command Line Tools(Swift 5.9+)。

## 授權

[MIT](LICENSE)
