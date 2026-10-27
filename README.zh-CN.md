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

- 🐢 **卡顿侦测**——找出真正让 Mac 变慢的原因，一句话说清楚：占满 CPU 的程序（例如卡住的同步程序连续一小时 90%）、此刻正从磁盘读回内存（MB/s）、CPU 过热降速、Intel 内显接高刷新率外接屏幕、连续开机多天且交换空间好几 GB。标题栏直接显示一个判断：顺畅／有点卡／很卡
- 🛠 **一键处理**——失控的程序可以降到后台（免 root、可还原，切换到该 App 时自动恢复）、重新启动或退出。菜单栏程序与 Apple 的后台工作进程（Spotlight、Siri 建议、照片分析）连续 5 分钟占满 CPU 会被自动压制，一闲下来就恢复——绝不碰 Dock 上的 App、系统界面、通话、远程桌面、录屏与 VPN——10 分钟后还会通知你
- 🧠 **智能自主释放**，三重触发、全部可调：
  1. **内核压力信号**——macOS 报告内存压力的瞬间立即响应
  2. **可用阈值**——可用内存低于 20%（可调）并持续 30 秒
  3. **定时计划**——每 15 分钟到 2 小时，喜欢固定节奏也可以
- 📈 **自适应冷却**——释放收效甚微（系统真的很忙）时自动加倍退避，不做无效空转；收效好则恢复正常节奏
- 🛑 **不帮倒忙、不白费力气**——释放过程交换空间一增长就立即停止；交换空间已达内存 ¼、或此刻正在换页时直接拒绝出手（那正是一般「内存清理」反而让电脑更卡的原因）。连续 3 次没回收到内存就暂停自动释放 6 小时，不再每小时白跑一次。另有低电量模式暂停、过热暂停
- 🪶 **极轻量**——闲置时约 0.4% CPU、35MB 内存；面板关着时完全不重画
- 🔍 **谁在占用内存**——「应用」页列出最耗内存的 App（辅助进程归入所属 App，与活动监视器口径相同），两次点击温和退出——8GB 机器上，关掉吃内存的 App 才是真正有效的解法
- 🌡 **「系统」页**——CPU 使用率、温度、功耗、风扇转速、热降频、电池健康、屏幕刷新率与开机常驻的后台服务，并判读 Mac 是不是因为「热」而变慢；「应用」页同时显示各 App 的 CPU 用量
- 🩺 **白话判读**——一句话告诉你现在顺不顺、是在压缩还是已经靠磁盘撑着、该做什么；悬停任何数字都有解释
- 🎛 **精致原生界面**——压力仪表环、App/联动/已压缩/缓存四项细目、实时换入速率、最近 5 分钟曲线（悬停读值）、看得出「真正有效几次」的释放记录
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

起跑前还会先检查：压缩池是否已占物理内存约 12% 以上、交换空间是否已达内存 ¼、此刻是否正从磁盘读回内存、压力是否已临界。若是，它会**直接拒绝出手并说明原因**，而不是假装有做事——8GB 机器实测，那正是所有「内存清理」反而让电脑更卡的状态（在那种状态下每小时定时释放 60 次全部回收 0MB，却把其他 App 挤进压缩）。

卡顿侦测每 10 秒读取一次所有用户进程的 CPU 时间（`proc_pid_rusage`，每轮约 5ms），辅助进程归入所属 App。持续 3 分钟占用超过半颗核心即列为失控；「降到后台」用的是 `setpriority(PRIO_DARWIN_PROCESS, …, PRIO_DARWIN_BG)`——macOS 自己给维护工作的后台状态——不需要 root，进程闲下来、切换到该 App、点「恢复」或退出内存管家时都会还原（清单有存档，即使崩溃也不会留下被压着的进程；动手前会用启动时间确认是同一个进程）。

老实说：如果你的 Mac 已经靠交换空间在撑，任何释放都救不了，只有关掉 App 才有用。内存管家会直接告诉你，并让你看到是哪些 App。

## 从源码构建

```bash
git clone https://github.com/xiewei3536/MemeryButler.git
cd MemeryButler
./build.sh   # 产出 dist/MemoryButler.app 与 dist/MemoryButler.dmg
```

要求：macOS 13+、Xcode Command Line Tools（Swift 5.9+）。

自我测试（无需操作界面）：

```bash
MEMORYBUTLER_SELFTEST=checks .build/debug/MemoryButler      # 533 项逻辑检查，返回 0/1（CI 也会跑）
MEMORYBUTLER_SELFTEST=1 dist/MemoryButler.app/Contents/MacOS/MemoryButler   # 实时读数 + 卡顿诊断
# + MEMORYBUTLER_SNAPSHOT_DIR=/tmp/shots [MEMORYBUTLER_SNAPSHOT_DARK=1] [MEMORYBUTLER_SNAPSHOT_DEMO=1] → 每个分页输出 PNG
# + MEMORYBUTLER_SELFTEST_RELEASE=1 → 另外实际跑一次释放
```

## 许可证

[MIT](LICENSE)
