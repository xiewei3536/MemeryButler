<div align="center">

<img src="docs/icon.png" width="128" alt="MemoryButler icon">

# MemoryButler

**A smart memory butler for low-RAM Macs — it watches, decides, and frees memory on its own, so your 8GB Mac stays smooth.**

**English** | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Architecture](https://img.shields.io/badge/Intel%20%7C%20Apple%20Silicon-Universal-8A2BE2)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
[![Release](https://img.shields.io/github/v/release/xiewei3536/MemeryButler)](https://github.com/xiewei3536/MemeryButler/releases/latest)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## Why

Macs with 8GB of RAM spend a lot of time swapping and compressing memory, and everything feels sluggish. MemoryButler is a tiny native menu bar app that monitors memory pressure in real time and **automatically frees memory at the right moment** — no clicking required, no root password, no Electron bloat (it idles at ~35MB itself).

## Features

- 🐢 **Lag detection** — finds what is actually making the Mac slow and says it in one line: an app hogging the CPU (e.g. a stuck sync client at 90% for an hour), memory being read back from disk *right now* (MB/s), CPU heat throttling, a high-refresh external display on Intel graphics, days of uptime with gigabytes of swap. The header shows a single verdict: Smooth / A bit slow / Laggy
- 🛠 **One-click fixes** — lower a runaway's priority (no root, reversible, restored automatically when you switch to that app), restart it, or quit it. Menu-bar apps and Apple's background workers (Spotlight, Siri Suggestions, Photos analysis) that hog the CPU for 5 minutes are calmed automatically and restored once idle — never Dock apps, Apple's UI, calls, remote desktop, recorders or VPNs — with a notification after 10 minutes
- 🧠 **Smart autonomous release** with three configurable triggers:
  1. **Kernel pressure signal** — reacts the instant macOS reports memory pressure
  2. **Low-available threshold** — available memory below 20% (adjustable) for 30 seconds
  3. **Schedule** — every 15 min to 2 hours, if you prefer a fixed rhythm
- 📈 **Adaptive cooldown** — if a release reclaims little (system genuinely busy), it backs off automatically instead of thrashing; big wins restore the normal pace
- 🛑 **Never harmful, never pointless** — the release stops the instant swap starts to grow, and declines outright when swap is already ≥ ¼ of RAM or the Mac is swapping right now (that's what makes "memory cleaners" backfire). After 3 runs that reclaim nothing, auto-free pauses for 6 hours instead of churning every hour. Also pauses in Low Power Mode and when the Mac is running hot
- 🪶 **Featherweight** — ~0.4% CPU and ~35MB at idle; the hidden panel never redraws
- 🔍 **Who's using memory** — an Apps tab lists the biggest apps (helper processes grouped under their app, same figures as Activity Monitor) with a two-click graceful Quit — on 8GB, closing the hog is the fix that actually works
- 🌡 **System tab** — CPU usage, temperature, power, fan speed, thermal throttling, battery health, display refresh rate and login-time background services, with a verdict on whether the Mac is slow because it is hot; the Apps tab also shows per-app CPU
- 🩺 **Plain-language verdict** — one line tells you whether the Mac is smooth, compressing, or already living on disk, and what to do; hover any figure for an explanation
- 🎛 **Polished native UI** — pressure ring gauge, App/Wired/Compressed/Cached breakdown, live swap rate, a 5-minute usage chart with hover readout, and a release history that shows how many runs actually helped
- 📊 **Menu bar at a glance** — live usage percentage right in your menu bar
- 🌐 **Multilingual UI** — English, Simplified Chinese, Traditional Chinese; switch instantly in-app or follow the system
- 🔄 **Built-in auto-update** — checks GitHub Releases periodically, notifies you of new versions, and downloads & installs in one click (no need to revisit the releases page)
- 🚀 **Universal Binary** — one app for both Intel and Apple Silicon, launch-at-login supported

## Install

1. Download `MemoryButler.dmg` from the [latest release](https://github.com/xiewei3536/MemeryButler/releases/latest)
2. Open it and drag **MemoryButler** into **Applications**
3. First launch: **right-click the app → Open** (it is ad-hoc signed, so Gatekeeper asks once)
4. Look for the chip icon in your menu bar — that's your butler on duty

## How it works

MemoryButler requests anonymous memory from the kernel at a controlled rate and touches every page (incompressible content, so the kernel can't just compress the ballast itself), which compels XNU to drop purgeable caches and compress idle pages of inactive apps. It then returns everything at once, leaving the system with more genuinely free memory. Entirely root-free, with hard safety limits, checked before every 64MB step: **swap growth → stop immediately** (the key one — on an already-swapping 8GB Mac, pushing further only writes other apps to disk), critical pressure → stop, thermal throttling → stop, plus total and time caps.

Before it even starts, it checks whether the compressor pool already holds more than ~12% of RAM, whether swap is already ≥ ¼ of RAM, whether the Mac is reading memory back from disk at that very moment, or whether pressure is already critical. If so, it **declines and says why** instead of pretending — measured on an 8GB Mac, that is exactly the state in which every "memory cleaner" makes things worse (an hourly schedule there reclaimed 0MB in 60 of 60 runs while pushing other apps into compression).

The lag detector samples every user process's CPU time every 10 seconds (`proc_pid_rusage`, ~5ms per pass) and groups helpers under their app. Something using over half a core for 3 minutes is reported as a runaway; "lower priority" uses `setpriority(PRIO_DARWIN_PROCESS, …, PRIO_DARWIN_BG)` — the same background state macOS gives its own maintenance work — which needs no root and is undone when the process goes idle, when you switch to the app, click Restore, or quit MemoryButler (the list is saved, so even a crash can't leave anything calmed; each process is re-identified by its start time before being touched).

Honest caveat: if your Mac is already living in swap, no release can fix that — only quitting apps can. MemoryButler tells you so, and shows you which ones.

## Build from source

```bash
git clone https://github.com/xiewei3536/MemeryButler.git
cd MemeryButler
./build.sh   # produces dist/MemoryButler.app and dist/MemoryButler.dmg
```

Requirements: macOS 13+, Xcode Command Line Tools (Swift 5.9+).

Self-tests (no UI needed):

```bash
MEMORYBUTLER_SELFTEST=checks .build/debug/MemoryButler      # 533 logic checks, exit code 0/1 (run in CI)
MEMORYBUTLER_SELFTEST=1 dist/MemoryButler.app/Contents/MacOS/MemoryButler   # live readings + lag diagnosis
# + MEMORYBUTLER_SNAPSHOT_DIR=/tmp/shots [MEMORYBUTLER_SNAPSHOT_DARK=1] [MEMORYBUTLER_SNAPSHOT_DEMO=1] → PNGs of every tab
# + MEMORYBUTLER_SELFTEST_RELEASE=1 → also run one real release
```

## License

[MIT](LICENSE)
