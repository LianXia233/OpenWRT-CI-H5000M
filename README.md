<div align="center">

# 🚀 Hiveton H5000M (MT5700M) 定制固件说明书

**基于 ImmortalWrt 主线（VIKINGYFY/immortalwrt @ owrt）源码 · 专为联发科 Filogic 平台 5G CPE 打造的高性能全功能固件**

[![ImmortalWrt](https://img.shields.io/badge/ImmortalWrt-VIKINGYFY%2Fowrt-00A0D0.svg?logo=openwrt&logoColor=white&style=flat-square)](https://github.com/VIKINGYFY/immortalwrt)
[![Platform](https://img.shields.io/badge/Platform-MediaTek%20Filogic-FF6B35.svg?style=flat-square)](#-一-硬件平台与固件底层概述)
[![Device](https://img.shields.io/badge/Device-Hiveton%20H5000M-blue.svg?style=flat-square)](#-目标设备与编译配置)
[![Modem](https://img.shields.io/badge/Modem-MT5700M%205G-success.svg?style=flat-square)](#1-mt5700m-5g-模组管理luci-app-mt5700)
[![Workflow](https://github.com/LianXia233/OpenWRT-CI-H5000M/actions/workflows/WRT-BUILD.yml/badge.svg?style=flat-square)](https://github.com/LianXia233/OpenWRT-CI-H5000M/actions)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg?style=flat-square)](LICENSE)

*全自动化 GitHub Actions 云端构建 · 深度适配 MT5700M 蜂窝模组 · 硬件级风扇温控与网络双链路无缝切换*

---

</div>

## ⚡ 快速开始

本仓库依托 GitHub Actions 实现自动化云端编译，无需本地搭建交叉编译环境。

### 1. 核心工作流一览

| 入口工作流 | 调度方式 | 核心功能与说明 |
| :--- | :--- | :--- |
| **WRT-BUILD** | 手动 `workflow_dispatch` | 手动编译 `MEDIATEK-WIFI-YES`（同样固定产出 `MT5700` / `MT5700M` 两套固件），支持临时传参追加插件或快速验证配置（`TEST=true`） |
| **MTK-AUTO** | 定时联动（`Auto-Clean` 完成后）/ 手动 | 每次运行固定产出**两套固件**（`MT5700` 与 `MT5700M` 各一个并行作业、各一个 Release），无需选择 |
| **Auto-Clean** | 每日 05:00 (CST) 定时 / 手动 | 定期清理历史构建资产（清理全部历史 Release 及孤立 Tag、30 天前的 Runs 记录；随后由 MTK-AUTO 触发新构建，故始终保有当日两套最新版本） |
| **Cache-Clean** | 每周定时 / 手动 | 释放 GitHub Actions 编译缓存，防止构建缓存膨胀或依赖冲突 |

### 2. 手动编译触发步骤

1. 进入仓库的 **Actions** 标签页。
2. 在左侧工作流列表中选择 **WRT-BUILD**。
3. 点击右侧 **Run workflow** 浮窗，按需填写参数（如测试模式、扩展插件列表）。
4. 编译完成后，**两套固件**（`MT5700` / `MT5700M`）将分别发布到仓库的 **Releases** 页面。

> [!TIP]
> 仓库根目录内置的 [`index.html`](./index.html) 为固件发布展示落地页，可直接启用 **GitHub Pages** 托管，亦可在本地浏览器打开直观浏览设备适配特性与下载链接。

---

## 📂 项目结构

```text
OpenWRT-CI-H5000M/
├── .github/workflows/
│   ├── WRT-CORE.yml          # 云编译底层执行引擎（被 WRT-BUILD / MTK-AUTO 复用）
│   ├── WRT-BUILD.yml         # 手动触发定制编译入口
│   ├── MTK-AUTO.yml          # 每日定时自动构建：固定产出 MT5700 / MT5700M 两套固件
│   ├── Auto-Clean.yml        # 历史 Release 与构建日志自动轮换清理
│   └── Cache-Clean.yml       # Actions 依赖缓存定时清理
├── Config/
│   ├── GENERAL.txt           # 全局内核模块、网络协议栈与 H5000M 专属插件清单
│   ├── MEDIATEK-WIFI-YES.txt # 针对 Hiveton H5000M 设备的 Target 与 Wi-Fi 驱动配置
│   ├── MT5700.txt            # 固件 A 的插件清单：luci-app-mt5700（新插件）
│   └── MT5700M.txt           # 固件 B 的插件清单：luci-app-mt5700m（旧插件，两者不共存于同一固件）
├── Scripts/
│   ├── Packages.sh           # 第三方扩展插件源同步与版本拉取
│   ├── Handles.sh            # HomeProxy 等网络组件预置与冲突修复
│   └── Settings.sh           # 系统默认 IP、Wi-Fi SSID/密码、主机名等底层初始化
├── index.html                # 固件发布落地页（支持 GitHub Pages）
├── LICENSE                   # 开源许可协议
└── README.md                 # 固件说明文档

```

---

## 🎯 目标设备与编译配置

本项目专为 **Hiveton H5000M（鼎桥 MT5700M 5G CPE）** 设备打造，配置目标高度收敛：

| 编译配置文件 | 目标平台架构 | 适配设备型号 | Wi-Fi 状态 | 适用场景 |
| --- | --- | --- | --- | --- |
| `MEDIATEK-WIFI-YES` | MediaTek Filogic | Hiveton H5000M | ✅ 启用 | 5G 移动蜂窝路由、无线 AP 与家庭主路由 |

---

## 📡 一、 硬件平台与固件底层概述

**Hiveton H5000M** 是一款面向高吞吐场景的旗舰级 5G CPE 路由器，核心用于将 5G 移动蜂窝网络高速转化为千兆局域网与双频无线覆盖。

| 核心维度 | 架构与实现方案 |
| --- | --- |
| 🏗️ **底层底包** | **基于 ImmortalWrt 主线（VIKINGYFY/immortalwrt @ owrt）源码构建**。内核深度集成硬件加速驱动（`kmod-cryptodev`、`kmod-tls`），全面释放加密隧道与代理分流的数据吞吐潜能。 |
| 🖥️ **计算平台** | 搭载 **联发科 (MediaTek) Filogic** 高性能网络处理器平台，原生支持硬件级 Packet Steering 与 Wi-Fi 6 (802.11ax) 高并发大带宽无线传输。 |
| 📶 **蜂窝模组** | 深度集成 **鼎桥 MT5700M 5G 模组**，支持三大运营商全网通 5G SA/NSA 双模，即插即用无需手动拨号配置。 |
| ❄️ **热设计架构** | 配备**主动可控调速静音散热风扇**，配合全铝散热片快速带走 5G 模组与 CPU 满载热量，保障 7×24 小时高吞吐不降频。 |

---

## 🧩 二、 核心专属 5G CPE 插件

固件深度集成硬件级适配套件：模组管理**每次构建同时产出两套固件**（`MT5700` / `MT5700M`，各自只含一套插件）；风扇温控同样按固件分流——`MT5700` 固件采用 **LianXia233** 的 [luci-app-h5000m-fancontrol](https://github.com/LianXia233/luci-app-h5000m-fancontrol)（Rust 重写版 v3.x），`MT5700M` 固件沿用 **FAN789** 原版（v2.1.1）；网络模式切换沿用 **FAN789** 的 H5000M 套件。

### 🎛️ 模组插件：每次构建固定产出两套固件

两套插件都独占 MT5700M 的 AT 串口，**同一份 `.config` 只能启用其中一个**，因此每次构建固定拆成两个并行作业，各出一套固件（无需在触发时做选择）：

| 固件 | 插件 | 形态 | 配置文件 |
| :--- | :--- | :--- | :--- |
| `MT5700` | [LianXia233/luci-app-mt5700](https://github.com/LianXia233/luci-app-mt5700) | LuCI 前端 + Rust/Tokio 常驻后端，12 个页面 | `Config/MT5700.txt` |
| `MT5700M` | [FAN789/luci-app-mt5700m](https://github.com/FAN789/luci-app-mt5700m) | LuCI 前端 + 原生 C 传输程序 `mt5700m-transport` | `Config/MT5700M.txt` |

* `MTK-AUTO`（每日定时）与 `WRT-BUILD`（手动）都是固定矩阵 `MODEM: [MT5700, MT5700M]`，一次运行产出**两个 Release**；`fail-fast: false`，一套失败不影响另一套。
* Release Tag 与固件文件名均带插件标识：`...-owrt-MT5700-<时间>` / `...-owrt-MT5700M-<时间>`，同一固件内绝不会同时出现两套插件。
* 两套插件源码都会 clone 到 `package/`，每次构建只编译对应那一套。
* CI 在 `make defconfig` 之后强制校验：两套主包同时为 `y`、或缺配套语言包，都会立刻失败（防止固件里出现两套抢同一串口的插件）。
* 两者都**不能**与 QModem 等同样占用模组串口的服务共存。

### 1. MT5700M 5G 模组管理（`luci-app-mt5700`）

作为 CPE 的网络命脉，该插件（当前跟随上游 **v1.30.4**，后端 `at-webserver` 1.29.0）以自有 Rust 后端独占模组 AT 串口，提供 12 个功能页面，统一入口为 **网络 → 移动网络 → 5G 模组管理**：

| 分组 | 页面 | 核心能力 |
| --- | --- | --- |
| 状态与链路 | 网络状态 | 网络制式（SA / NSA）、RSRP / RSRQ / SINR、载波聚合、服务小区与频段、运营商 / SIM 状态；实时速率取自内核网卡计数，**不占用 AT 通道** |
| 接入配置 | 网络设置 · 拨号设置 | APN / PDP / 鉴权、自动拨号与断线重连；`iface_v4` / `iface_v6` 支持自动复用已有接口或创建 `MT5700M` 接口并登记防火墙区域 |
| 无线调优 | 全网扫频 · 定时锁频 | 频段与小区扫描、按计划的锁频 / 锁小区任务 |
| 模组维护 | 模组设置 · 模组升级 | 模组参数与工作模式、USB 组合、FOTA 升级 |
| 短信 | 短信中心 · 短信设置 | UTF-16 中文与 emoji、多段长短信、会话与去重、发送任务进度，确认不明时不自动重发 |
| 调试与运维 | AT 调试终端 · 运行日志 · 服务配置 | 手工下发 AT 指令、后端日志检索、串口与后端参数配置 |

* 🩺 **事件通知与自愈**：信号定时巡检、事件推送（Webhook / 邮件 / QQ 机器人等），并区分「数据链路已连接」与「互联网验证通过」，按条件恢复数据会话。
* ❄️ **温度联动（风扇控制器内置）**：风扇温控插件 v3.x 每 30 秒经该后端的本地 RPC（`127.0.0.1:8765`，newline-JSON）下发一次 `AT^CHIPTEMP?`，取 12 路芯片温度的峰值，按旧格式（`updated=` + `temperature=`）原子写入 `/var/run/mt5700m/temperature` 供调速曲线使用；AT 串口仍由后端独占，查询失败（后端未运行）只是该周期无模组温度，不影响其余传感器。
* 🧱 **服务与配置**：服务 `/etc/init.d/at-webserver`（procd，含接口拉起与开机自愈）、配置 `/etc/config/at-webserver`、后端 `/usr/bin/at-webserver-rust`；rpcd ucode 插件经 `nc 127.0.0.1 <port>` 访问后端（`nc` / `timeout` 由 busybox 默认提供）。
* 🛠️ **构建方式（本仓库深度适配）**：后端为静态 musl 二进制，CI 在编译固件前用 rustup + zig 交叉编译出 aarch64 产物并交给包内预编译分支安装——buildroot 编译阶段没有 cargo，也不需要在 CI 里现编 host rust（详见更新日志）。

> [!IMPORTANT]
> **与旧插件 `luci-app-mt5700m`、QModem 不兼容。** 三者都独占同一 AT 串口，同时安装会互相抢口，表现为 AT 指令超时、拨号状态来回跳、模组「无响应」。本仓库通过「每个固件只启用一套」来避免这个问题（见上文说明），请勿在固件装好后再从软件源手工加装另一套。

#### 另一套固件：`luci-app-mt5700m`（`MT5700M`）

需要旧插件的能力（原生 C 传输程序 `mt5700m-transport`、`/etc/mt5700m/traffic-history` 流量历史、链路健康自愈）时，直接下载同批次发布的 `MT5700M` 固件（对应 `Config/MT5700M.txt`）：

* 入口同样是「网络 → 移动网络 → MT5700M 模组」（`admin/modem/mt5700m`），运行期由 `mt5700m-transport` 独占 AT 串口，并自行维护模组温度缓存 `/var/run/mt5700m/temperature`，随本套固件发货的风扇温控插件（FAN789 原版）直接复用该文件。
* 该固件下不会编译 `luci-app-mt5700`；风扇温控沿用 FAN789 原版（v2.1.1，纯 shell，无需 Rust 预编译）；语言包为 `luci-i18n-mt5700m-zh-cn`。
* 旧插件额外依赖 `flock`（该依赖只在 `Config/MT5700M.txt` 中启用）。

### 2. 硬件级智能风扇温控 (`luci-app-h5000m-fancontrol`)

针对 5G 蜂窝模组在高负载上传下载时的剧烈发热，提供精准的闭环散热管理。风扇插件**按固件分流**（两个仓库包名相同，同一 package 树只能存在一套，每个固件只编其一；启用项在 `Config/GENERAL.txt`，来源由 `Scripts/Packages.sh` 按 `WRT_MODEM` 条件克隆）：

| 固件 | 插件来源 | 形态 |
| :--- | :--- | :--- |
| `MT5700` | [LianXia233/luci-app-h5000m-fancontrol](https://github.com/LianXia233/luci-app-h5000m-fancontrol) | Rust 重写版 **v3.2.0**：零依赖静态 musl 控制器 + 六 TAB LuCI 界面 |
| `MT5700M` | [FAN789/luci-app-h5000m-fancontrol](https://github.com/FAN789/luci-app-h5000m-fancontrol) | 原版 **v2.1.1**：shell 控制器（纯脚本，无 Rust 依赖） |

两者的服务名（`/etc/init.d/h5000m-fancontrol`）、菜单入口（`admin/system/h5000m_fancontrol`）、UCI 选项与温度缓存路径完全一致；模组温度均取自 `/var/run/mt5700m/temperature`（`MT5700` 固件由风扇控制器经 at-webserver RPC 每 30 秒写入，见上文温度联动；`MT5700M` 固件由 `mt5700m-manager` 维护）。

`MT5700` 固件上 v3.x 的增强特性：

* 🦀 **原生 Rust 控制器**：零依赖静态 musl 二进制 `/usr/sbin/h5000m-fancontrol`（CI 用 rustup 交叉编译后经包内预编译分支安装），procd 常驻、崩溃自动拉起；保存配置只发 `SIGHUP` 热加载，不重启风扇。
* 🌡️ **多传感器融合**：实时采集 SoC 热区 / hwmon 与 MT5700M 基带模组两路温度，取最高值驱动曲线；任一传感器缺失或读数异常（不可读 / 超界 / 过期）一律视为未知，绝不折算成 0 ℃ 进入控制输入。
* 🔒 **内核安全兜底**：控制器从不触碰 CPU 热区策略，只接管风扇 cooling-maps；CPU 降频与高温 / 临界保护由内核 `step_wise` 继续兜底，风扇失联自动回退全速（fail-safe PWM 255）。
* 🌀 **PWM 阶梯变速**：静音 / 均衡 / 性能 / 自定义四条曲线，支持起转 PWM 与起转助推、温度迟滞与降速延时，兼顾待机静音与满载散热。
* 🖥️ **六 TAB LuCI 界面**：总览 / 风扇控制 / 曲线 / 温度监控 / 系统设置 / 诊断，原生 SVG 风扇图与曲线图，深浅色自适应。

### 3. 网络模式无缝切换 (`luci-app-h5000m-netmode`)

为 5G 蜂窝与传统 WAN 口有线光纤双接入场景提供一键化管理：

* 🔄 **四种模式一键指派**：`有线优先`（`wan_first`）、`5G 优先`（`modem_first`）、`仅有线`（`wan_only`）、`仅 5G`（`modem_only`）。
* ⚡ **路由优先级倒换**：通过 uci 调整 `wan` / `MT5700M` 的 `metric` 与默认路由标记，切换后 `network reload` 生效；主链路默认路由消失时由内核路由自动改走备用链路（**不依赖 mwan3**）。

---

## 🛠️ 三、 系统级扩展与服务支持

* **加密加速引擎**：默认集成 `kmod-cryptodev` 与 `kmod-tls`，使 HomeProxy 等科学分流工具在千兆满速下显著降低 CPU 占用。
* **USB 驱动协议栈**：打包 `kmod-usb-core`、`kmod-usb3`、`kmod-usb-net-qmi-wwan` 及 `kmod-usb-serial`，保障外部拓展模组即插即用。
* **轻量 NAS 与存储扩展**：原生支持 NVMe 固态硬盘（`kmod-nvme`）挂载，结合 BTRFS 文件系统与 Samba4，打造稳定私有云。
* **安全异地组网**：内置 EasyTier（含 LuCI 配置界面）与 `kmod-wireguard` 内核模块；Tailscale / ZeroTier 等未预置，需要时自行安装。

---

## 💖 鸣谢与致敬

本固件的自动化构建体系、底层调优与硬件模组适配离不开以下优秀的开源项目与开发者：

* 🐧 **[ImmortalWrt](https://github.com/immortalwrt/immortalwrt/?utm_source=gemini)**：提供功能丰富、性能卓越的主线底层路由源码。
* 👤 **[VIKINGYFY](https://github.com/VIKINGYFY?utm_source=gemini)**：为本项目提供经过长期实机验证的云端构建脚手架、底包配置与插件优化模板。
* 👤 **[LianXia233](https://github.com/LianXia233?utm_source=gemini)**：提供 [luci-app-mt5700](https://github.com/LianXia233/luci-app-mt5700?utm_source=gemini)（编入 `MT5700` 固件的模组管理插件，LuCI 前端 + Rust/Tokio 后端单包融合）与 [luci-app-h5000m-fancontrol](https://github.com/LianXia233/luci-app-h5000m-fancontrol?utm_source=gemini)（风扇温控 Rust 重写版，编入 `MT5700` 固件）。
* 👤 **[FAN789](https://github.com/FAN789?utm_source=gemini)**：为 Hiveton H5000M 研发了硬件配套的 [luci-app-h5000m-fancontrol](https://github.com/FAN789/luci-app-h5000m-fancontrol?utm_source=gemini)（原版 v2.1.1 编入 `MT5700M` 固件；`MT5700` 固件采用其 Rust 重写演进分支）与 [luci-app-h5000m-netmode](https://github.com/FAN789/luci-app-h5000m-netmode?utm_source=gemini) 插件，其 [luci-app-mt5700m](https://github.com/FAN789/luci-app-mt5700m?utm_source=gemini) 编入 `MT5700M` 固件。

---

> 📅 **维护周期**：持续随 ImmortalWrt 主线（VIKINGYFY/immortalwrt @ owrt）更新
> 📜 **许可协议**：本项目基于 [GPL-3.0](https://www.google.com/search?q=LICENSE&utm_source=gemini) 开源
