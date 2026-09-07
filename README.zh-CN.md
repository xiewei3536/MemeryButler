<div align="center">

<img src="docs/icon.png" width="128" alt="内存管家图标">

# 内存管家 MemoryButler

**为小内存 Mac 而生的智能管家——自主监控、自主决策、自主释放，让 8GB 的 Mac 也能流畅运行。**

[English](README.md) | **简体中文** | [繁體中文](README.zh-TW.md)

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Architecture](https://img.shields.io/badge/Intel%20%7C%20Apple%20Silicon-Universal-8A2BE2)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
[![Release](https://img.shields.io/github/v/release/xiewei3536/MemeryButler)](https://github.com/xiewei3536/MemeryButler/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## 为什么需要它

8GB 内存的 Mac 常常在交换空间和压缩内存之间挣扎，整台机器越用越卡。内存管家是一个极轻量的原生菜单栏 App，实时监控内存压力，**在对的时机自动出手释放内存**——不用点按、不用 root 密码、不是臃肿的 Electron（它自己常驻仅约 35MB）。

## 功能特色

- 🧠 **智能自主释放**，三重触发、全部可调：
  1. **内核压力信号**——macOS 报告内存压力的瞬间立即响应
  2. **可用阈值**——可用内存低于 20%（可调）并持续 30 秒
  3. **定时计划**——每 15 分钟到 2 小时，喜欢固定节奏也可以
- 📈 **自适应冷却**——释放收效甚微（系统真的很忙）时自动加倍退避，不做无效空转；收效好则恢复正常节奏
- 🛑 **交换空间刹车**——释放过程一旦发现交换空间开始增长立即停止，因此只清缓存、只压缩闲置页，绝不会把其他 App 写进磁盘（那正是一般「内存清理」反而让电脑更卡的原因）。另有低电量模式暂停、过热暂停、压力临界刹车
- 🔍 **谁在占用内存**——「应用」页列出最耗内存的 App（辅助进程归入所属 App，与活动监视器口径相同），两次点击温和退出——8GB 机器上，关掉吃内存的 App 才是真正有效的解法
- 🌡 **「系统」页**——CPU 使用率、温度、功耗、风扇转速、热降频、电池健康、屏幕刷新率与开机常驻的后台服务，并判读 Mac 是不是因为「热」而变慢；「应用」页同时显示各 App 的 CPU 用量
- 🩺 **白话判读**——一句话告诉你现在顺不顺、是在压缩还是已经靠磁盘撑着、该做什么；悬停任何数字都有解释
- 🎛 **精致原生界面**——压力仪表环、App/联动/已压缩/缓存四格统计、最近 5 分钟实时曲线（悬停读值）、完整释放记录
- 📊 **菜单栏一目了然**——使用率百分比直接显示在菜单栏
- 🌐 **多语言界面**——英文、简体中文、繁体中文，App 内即时切换或跟随系统
- 🔄 **内置自动更新**——定期检查 GitHub Releases，新版本推送通知，App 内一键下载安装，无需回到 release 页重新下载
- 🚀 **Universal Binary**——一个 App 同时支持 Intel 与 Apple Silicon，支持登录时自动启动

## 安装

1. 到[最新版本](https://github.com/xiewei3536/MemeryButler/releases/latest)下载 `MemoryButler.dmg`
2. 打开后把 **MemoryButler** 拖进「**应用程序**」
3. 首次启动：**右键点击 App → 打开**（ad-hoc 签名，Gatekeeper 只会问这一次）
4. 看菜单栏上的芯片图标——你的管家已就位

## 工作原理

内存管家以受控速度向内核索取匿名内存并触碰每一页（内容不可压缩，内核才不会只是把压载本身压缩掉），迫使 XNU 丢弃可清除缓存、压缩不活跃 App 的闲置页，随后一次性归还，系统便多出真正可用的内存。全程免 root，每前进 64MB 就检查一次硬性安全机制：**交换空间一增长 → 立即停止**（最关键的一道——已在使用 swap 的 8GB 机器上，再往下挤只是把别的 App 写进磁盘）、压力临界 → 停止、过热 → 停止，以及总量与时间上限。

起跑前还会先检查：压缩池是否已占物理内存约 12% 以上、交换空间此刻是否正在增长、压力是否已临界。若是，它会**直接拒绝出手并说明原因**，而不是假装有做事——8GB 机器实测，那正是所有「内存清理」反而让电脑更卡的状态。

老实说：如果你的 Mac 已经靠交换空间在撑，任何释放都救不了，只有关掉 App 才有用。内存管家会直接告诉你，并让你看到是哪些 App。

## 从源码构建

```bash
git clone https://github.com/xiewei3536/MemeryButler.git
cd MemeryButler
./build.sh   # 产出 dist/MemoryButler.app 与 dist/MemoryButler.dmg
```

要求：macOS 13+、Xcode Command Line Tools（Swift 5.9+）。

## 许可证

[MIT](LICENSE)
