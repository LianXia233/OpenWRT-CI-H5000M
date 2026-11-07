<div align="center">

# 🚀 Hiveton H5000M (MT5700M) 5G CPE 定制固件

**基于 ImmortalWrt 主线源码 · 专为联发科 Filogic 旗舰 5G CPE 打造的高性能全功能固件**

[![ImmortalWrt](https://img.shields.io/badge/ImmortalWrt-VIKINGYFY%2Fowrt-00A0D0.svg?logo=openwrt&logoColor=white&style=flat-square)](https://github.com/VIKINGYFY/immortalwrt)
[![Platform](https://img.shields.io/badge/Platform-MediaTek%20Filogic-FF6B35.svg?style=flat-square)](#-一-硬件平台与固件底层架构)
[![Device](https://img.shields.io/badge/Device-Hiveton%20H5000M-blue.svg?style=flat-square)](#-二-双模组生态方案)
[![Modem](https://img.shields.io/badge/Modem-MT5700M%205G-success.svg?style=flat-square)](#-二-双模组生态方案)
[![CI Build](https://img.shields.io/github/actions/workflow/status/LianXia233/OpenWRT-CI-H5000M/WRT-BUILD.yml?branch=main&label=CI%20Build&style=flat-square&logo=githubactions&logoColor=white)](https://github.com/LianXia233/OpenWRT-CI-H5000M/actions)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg?style=flat-square&logo=gnu&logoColor=white)](LICENSE)

<p align="center">
  <b>全自动化 GitHub Actions 云端构建 · 深度适配 MT5700M 蜂窝模组 · 硬件级风扇温控与网络双链路无缝切换</b><br>
  每次自动构建固定产出 <b>MT5700</b>（现代化 Rust 单包）与 <b>MT5700M</b>（经典成熟方案）两套独立固件
</p>

</div>

---

## ⚡ 核心亮点特性

- 🚀 **专为 H5000M 旗舰定制**：深度融合联发科 MediaTek Filogic MT7987A 处理器与 MT7996E Wi-Fi 7 无线芯片组，原生释放千兆全双工移动网络吞吐。
- 📦 **双模组生态每次并行产出**：
  - **`MT5700` 固件**：集成 [luci-app-mt5700](https://github.com/LianXia233/luci-app-mt5700)（Rust/Tokio 异步常驻后端、12 个现代管理页面、真实射频数据可信）+ [luci-app-h5000m-fancontrol](https://github.com/LianXia233/luci-app-h5000m-fancontrol)（Rust 重写版 v3.x 风扇温控）。
  - **`MT5700M` 固件**：集成 [FAN789/luci-app-mt5700m](https://github.com/FAN789/luci-app-mt5700m)（原生 C 传输程序 `mt5700m-transport`）+ 原版 shell 风扇温控。
- ❄️ **硬件级闭环散热保护**：SoC 核心温区与 MT5700M 模组 12 路硬件温感联动轮询，多阶 PWM 变速，兼顾低负载静音与满载散热。
- 🔄 **网络链路智能调度**：集成 `luci-app-h5000m-netmode`，支持「仅 5G 蜂窝」「仅 WAN 有线」「有线优先」「5G 优先」四种模式一键切换与毫秒级故障倒换。
- 🛠️ **系统级硬件加速**：内置 `kmod-cryptodev`、`kmod-tls` 硬件加解密引擎加速，原生支持 NVMe 固态硬盘（BTRFS / Samba4）与 EasyTier 异地安全组网。

---

## ⚙️ 固件默认出厂配置

| 参数维度 | 默认出厂值 | 详细说明 |
|:---|:---|:---|
| **后台管理地址** | `192.168.10.1` | Web 管理界面 IPv4 入口 |
| **登录账号 / 密码** | `root` / **空（首次无密码）** | 建议首次进入系统后立即修改密码 |
| **局域网主机名** | `OWRT` | 本地网络标识 |
| **默认 Wi-Fi SSID** | `OWRT` | 2.4G 与 5G 双频合一名称 |
| **默认 Wi-Fi 密码** | `12345678` | WPA/WPA2 混合加密标准 |
| **无线频宽（WiFi 7）** | 2.4G `40MHz` · 5G `160MHz` | 802.11be（EHT 世代），跑满高并发无线带宽 |
| **系统时区与国家码** | `Asia/Shanghai` (`CST-8`) / `CN` | 保证 NTP 时钟校准与合规射频信道 |

---

## 📡 一、 硬件平台与固件底层架构

**Hiveton H5000M** 是一款面向极速数据吞吐场景的旗舰级 5G CPE 路由器：

| 核心维度 | 架构与实现方案 |
|:---|:---|
| 🏗️ **底层源码基石** | **基于 ImmortalWrt 主线（VIKINGYFY/immortalwrt @ owrt）源码构建**。内核深度集成硬件加速驱动（`kmod-cryptodev`、`kmod-tls`），全面卸载加密隧道与代理分流的数据吞吐压力。 |
| 🖥️ **计算平台** | 搭载 **联发科 (MediaTek) Filogic MT7987A** 高性能网络处理器平台，原生支持硬件级 Packet Steering 与 Wi-Fi 7 (802.11be) 超高速率无线传输。 |
| 📶 **蜂窝通信模组** | 深度集成 **鼎桥 MT5700M 5G 模组**，支持三大运营商 5G SA/NSA 双模全网通，开箱即用自动对账拨号。 |
| ❄️ **散热工程设计** | 配备**主动可控调速静音风扇**与全铝散热构件，精准带走 5G 基带与 SoC 满载积热，保障 7×24 小时满速不降频。 |

---

## 🎛️ 二、 双模组生态方案对比

MT5700M 模组的主控 AT 串口具有硬件独占性。**为杜绝多进程抢占 TTY 导致的 AT 乱序与指令假死，本仓库每次构建固定并行产出两套互相隔离的固件**：

| 对比维度 | `MT5700` 固件（现代推荐） | `MT5700M` 固件（经典方案） |
|:---|:---|:---|
| **模组控制插件** | [LianXia233/luci-app-mt5700](https://github.com/LianXia233/luci-app-mt5700) | [FAN789/luci-app-mt5700m](https://github.com/FAN789/luci-app-mt5700m) |
| **后台架构** | **Rust + Tokio** 异步非阻塞事件驱动常驻后端 (`at-webserver-rust`) | 原生 C 传输程序 `mt5700m-transport` |
| **管理界面** | 12 个原生现代化 LuCI 控制台（状态/APN/扫频/锁频/拨号/升级/短信/终端等） | 经典 LuCI 模组控制面板与状态大屏 |
| **风扇温控套件** | [luci-app-h5000m-fancontrol](https://github.com/LianXia233/luci-app-h5000m-fancontrol)（**Rust 重写版 v3.x**） | 原版 shell 风扇控制器（纯脚本） |
| **温度采集机制** | 风扇控制器每 30 秒经本地 RPC 获取 12 路芯片峰值温度，原子写入缓存 | 由 `mt5700m-manager` 轮询写入模组温度缓存 |
| **短信中心** | 聊天式 IM 时间轴、长短信拼接、本地 ChaCha20 加密归档 | 配合 `sms-tool_q` 实现短信基础查看 |
| **配置文件** | `Config/MT5700.txt` | `Config/MT5700M.txt` |

> [!WARNING]
> 两套插件底层互不兼容且严禁共存。本仓库构建流水线在 `make defconfig` 后执行强校验，若两套同时启用将直接阻断构建。请勿在刷好固件后从软件源跨版本安装另一套。

---

## 🧩 三、 CPE 专属套件详解

### 1. 硬件级智能风扇温控 (`luci-app-h5000m-fancontrol`)
针对 5G 模组在极限工况下的剧烈发热，提供闭环温控：
- **`MT5700` 固件搭载 Rust 重写版 (v3.x)**：
  - 零依赖静态 musl 二进制控制器，procd 进程守护，配置变动热加载（`SIGHUP`）；
  - 融合 CPU SoC 热区与基带模组最高结温，拒绝将无效读数折算为 0℃；
  - 具备静音/均衡/性能/自定义 4 条曲线、起转脉冲助推与迟滞降速保护；
  - 6 TAB LuCI 界面，原生矢量 SVG 风扇动效与温升曲线。
- **`MT5700M` 固件搭载原版 (v2.1.1)**：成熟稳定的经典 shell 脚本控制器。

### 2. 网络模式智能调度 (`luci-app-h5000m-netmode`)
- **四种工作模式一键指派**：`有线优先`（`wan_first`）、`5G 优先`（`modem_first`）、`仅有线`（`wan_only`）、`仅 5G`（`modem_only`）；
- **内核路由极速切换**：动态调整 `wan` 与 `MT5700M` 承载接口的 metric 权值，主链路中断时内核自动切换至备选链路，无需繁重多拨组件。

---

## 🚀 四、 自动化云端编译与构建矩阵

无需在本地部署复杂的交叉编译链，全流程依托 GitHub Actions 云端流水线构建：

### 工作流一览

| 工作流文件 | 调度机制 | 核心功能与产出 |
|:---|:---|:---|
| **`WRT-BUILD.yml`** | 手动 `workflow_dispatch` | 手动定制编译：固定并行产出 `MT5700` / `MT5700M` 两套固件；支持追加临时参数或开启 `TEST=true` 快速语法自检 |
| **`MTK-AUTO.yml`** | 每日定时 / 联动触发 | 自动化构建并发布 H5000M 的两套最新固件，发布为两个独立的 Release |
| **`Auto-Clean.yml`** | 每日定时 05:00 (CST) | 自动保留最新 Release，清理历史废旧 Tag 与 30 天以前的 Actions 日志 |
| **`Cache-Clean.yml`** | 每周定时 / 手动 | 回收 Actions 编译缓存，避免依赖冲突与缓存膨胀 |

### 固件命名规则

编译产物在 Release 中以固件方案精确隔离：
- `H5000M-owrt-MT5700-<时间>-sysupgrade.bin`
- `H5000M-owrt-MT5700M-<时间>-sysupgrade.bin`

---

## 五、 在线升级插件与机型预设

两套固件都内置 [luci-app-online-upgrade](https://github.com/LianXia233/luci-app-online-upgrade)（Rust 后端 + ucode rpcd + LuCI 前端），并在构建期完成以下三件事：

| 阶段 | 入口脚本 | 作用 |
|:---|:---|:---|
| 导入 | `Scripts/Packages-OnlineUpgrade.sh` | 上游是「包即仓库根」，clone 到 `package/` 后清 `.git`/`.github`，CRLF 归一为 LF 并按字节复核；断言 `feeds/luci/luci.mk`、`./root/usr/bin/online-upgrade` 安装项、Rust 工程目录、默认 UCI 配置与 release profile 收敛项；核对 `90-online-upgrade-auto` 的存在性守卫与三处路径一致（`root/usr/bin/online-upgrade` → `$(1)/usr/bin/online-upgrade` → 设备端 `/usr/bin/online-upgrade`） |
| 选中 | `Scripts/Settings.sh` | 追加 `CONFIG_PACKAGE_luci-app-online-upgrade=y`；`rpcd-mod-ucode` / `ucode-mod-fs` / `ucode-mod-uci` 由包 `DEPENDS` 自动拉取，`make defconfig` 之后硬性校验四者均为 `y` |
| 预设 | `Scripts/OnlineUpgradePreset.sh` | 按机型生成 `files/etc/config/online-upgrade`（overlay 覆盖包自带 conffile） |
| 预编译 | `WRT-CORE` 的 `Cross Compile Online Upgrade Backend` | 上游 `Build/Prepare` 与 `Build/Compile` 均为空，二进制在此编译后落到包内 `root/usr/bin/online-upgrade`，否则会装出空壳 |

各机型的出厂预设与本仓库实际产物一一对应（构建期由变量推导，不写死静态文件）：

| 机型 | `repo` | `tag` | `firmware_pattern` |
|:---|:---|:---|:---|
| `MT5700` 固件 | `LianXia233/OpenWRT-CI-H5000M` | `latest@^MEDIATEK-WIFI-YES-VIKINGYFY-owrt-MT5700-` | `^mediatek-filogic-hiveton_h5000m-.*-MT5700-.*\.bin$` |
| `MT5700M` 固件 | `LianXia233/OpenWRT-CI-H5000M` | `latest@^MEDIATEK-WIFI-YES-VIKINGYFY-owrt-MT5700M-` | `^mediatek-filogic-hiveton_h5000m-.*-MT5700M-.*\.bin$` |

- `90-online-upgrade-auto` 的存在性守卫：上游 `98a966a`（2026-11-08）已改为 `[ -x /usr/bin/online-upgrade ]`，不再引用 v1 的 `online-upgrade.sh`。本仓库按内容判定——仅当检测到 v1 路径时才改写，上游已修复则跳过；无论是否改写都断言最终代码行引用 v2 路径（注释中的历史说明不计入判定），并核对三处路径一致。
- `tag` 的 `latest@<正则>` 语义取自 `rust/src/github.rs`：只在 tag 名匹配该正则的 Release 里取最新，因此 `MT5700` 不会拿到 `MT5700M` 的产物；模组标识两侧都带连字符，`-MT5700-` 不会匹配 `-MT5700M-`（反向同理）。
- `firmware_pattern` 结尾锚定 `.bin`，排除同批上传的 `.manifest` 与 `Config-*.txt`。
- 预设只写入代码真正读取的键：`repo`、`tag`、`proxy`、`firmware_pattern`、`min_size_mb`、`expected_sha256`、`dl_workers`、`dl_chunk_mb`、`dl_stall_sec`、`dl_retries`（section 为 `online-upgrade.settings`）。上游默认配置里的 `enabled` 与 `keep_config` 在本版本 Rust 与 rpcd 代码中均未被读取，故不写入，避免"配了却不起作用"。

### Rust 后端编译方式

- 使用 **Rust 官方工具链**（rustup stable + `aarch64-unknown-linux-musl` std），不使用 `feeds/packages/lang/rust`：后者需现场编译 host LLVM（1~2 小时、约 20GB 磁盘），其产物链接目标板的 musl 动态库，与本仓库既有的静态 musl 二进制策略及 panic/strip 处理不一致。
- 交叉链接器用 zig cc（本仓库既有方案，与上游 `scripts/sdk-build.sh` 一致）：Rust 的 musl target 不自带 libc 与启动对象，zig cc 一次提供 libc 与 C 编译器；该依赖树含 `ring` 的 C 代码。
- `-C target-cpu=cortex-a53` 与固件 `ARCH_PACKAGES=aarch64_cortex-a53` 对齐；不使用 `target-cpu=native` —— runner 是 x86_64，native 会把宿主机指令集编进 aarch64 产物，跨架构不可用。
- 产物收敛由上游 `[profile.release]` 保证（`opt-level="z"`、`lto=true`、`codegen-units=1`、`panic="abort"`、`strip=true`），导入脚本对这些键做断言，避免上游改动导致体积与符号策略漂移。
- 缓存 `~/.cargo/registry`、`~/.cargo/git` 与后端 `target` 目录，键含 `Cargo.lock` 的 sha256；重复构建不再全量重编译依赖树。

---

## 📂 项目结构一览

```text
OpenWRT-CI-H5000M/
├── .github/workflows/
│   ├── WRT-CORE.yml          # 底层通用编译引擎
│   ├── WRT-BUILD.yml         # 手动触发定制编译入口
│   ├── MTK-AUTO.yml          # 定时自动编译发版（固定并行产出双固件）
│   ├── Auto-Clean.yml        # 历史制品与日志轮换清理
│   └── Cache-Clean.yml       # Actions 构建缓存回收
├── Config/
│   ├── GENERAL.txt           # 全局内核模块、网络协议栈与基础功能包
│   ├── MEDIATEK-WIFI-YES.txt # Hiveton H5000M 硬件板级与 Wi-Fi 驱动配置
│   ├── MT5700.txt            # 方案 A 插件清单：luci-app-mt5700 + Rust 风扇温控
│   └── MT5700M.txt           # 方案 B 插件清单：luci-app-mt5700m + 原版风扇温控
├── Scripts/
│   ├── Packages.sh           # 第三方源码 Feed 同步与条件克隆
│   ├── Packages-OnlineUpgrade.sh  # 在线升级插件导入与结构/守卫断言
│   ├── OnlineUpgradePreset.sh     # 按机型生成 files/etc/config/online-upgrade
│   ├── Handles.sh            # 组件依赖适配与补丁注入
│   └── Settings.sh           # 默认出厂 IP、Wi-Fi 与时区编译期配置
├── index.html                # 固件发布聚合展示落地页
└── README.md                 # 固件说明文档
```

---

## 💖 致敬与鸣谢

* 🐧 **底包源码**：[immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) · [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt)（优质可靠的 Filogic 底层源码与构建框架）
* 👤 **编译框架**：[VIKINGYFY](https://github.com/VIKINGYFY)（成熟的 OpenWrt 云编译编排体系）
* 👤 **模组与专属套件**：[LianXia233](https://github.com/LianXia233)（[luci-app-mt5700](https://github.com/LianXia233/luci-app-mt5700) 现代单包与 [luci-app-h5000m-fancontrol](https://github.com/LianXia233/luci-app-h5000m-fancontrol) Rust 温控）· [FAN789](https://github.com/FAN789)（[luci-app-mt5700m](https://github.com/FAN789/luci-app-mt5700m) 经典模组驱动与 [luci-app-h5000m-netmode](https://github.com/FAN789/luci-app-h5000m-netmode) 多网切换套件）

---

> 📜 **许可协议**：本项目基于 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 开源发布。
