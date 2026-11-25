# vpp-router 移植适配 H5000M：可行性报告与实施方案

| 项目 | 内容 |
|:---|:---|
| 报告日期 | 2026-11-26 |
| 源项目 | [qqdwdbb/vpp-router](https://github.com/qqdwdbb/vpp-router)，分析基于 `main` 分支 `4b1cbf3` |
| 目标项目 | [LianXia233/OpenWRT-CI-H5000M](https://github.com/LianXia233/OpenWRT-CI-H5000M) |
| 目标硬件 | Hiveton H5000M：MT7987A（4×Cortex-A53 2.4GHz）、1GB DDR4、8GB eMMC、2×2.5G 以太网、MT7992 WiFi7、MT5700M 5G 模组（USB） |
| 目标系统 | ImmortalWrt（VIKINGYFY/immortalwrt `owrt` 分支）、Linux 6.18、aarch64_cortex-a53、musl、procd/netifd/UCI/LuCI |
| 结论级别 | **有条件可行**；不建议整包直接移植，建议先做 P0 验证，再按混合架构或控制面移植推进 |

---

## 0. 结论摘要

1. **“能不能跑”**：VPP 源码已有少量 musl 适配，预期可以交叉编译到 aarch64/musl（需 P0 实测确认）；并且可以只用 `af_packet` 插件接管 H5000M 的板载 2.5G 网口，**不需要 DPDK、不需要大页、不需要 UIO/VFIO**。这是本项目最重要的可行性基础。
2. **“能不能直接用”**：不能。vpp-router 的安装器强依赖 Debian/Ubuntu 或 Fedora、`apt/dnf`、systemd、bash 4、NetworkManager、`patchelf`、`systemd-coredump`、大页和 UIO。OpenWrt 使用 BusyBox ash、procd、netifd、UCI、opkg/apk、musl，**安装器需要整体重写**（约 3400 行 bash 不能复用）。
3. **最大的硬约束**：
   - **DPDK 没有 MediaTek `mtk_eth_soc` PMD**，板载两个 2.5G 口只能走 AF_PACKET（或自研原生 PMD/AF_XDP，成本高）。
   - **WiFi（MT7992）与 5G 模组（MT5700M）必须留在 Linux**：VPP 没有 mt76/USB modem 驱动，无法直接接管；WiFi/模组流量要经 TAP 或 AF_PACKET 回注。
   - **内存只有 1GB**：vpp-router 在小于 3GB 的机器上默认 `main-heap-size 512M`、`buffers-per-numa 16384`，对 H5000M 偏大，需要压到约 192–256MB 堆 + 8192 buffers，并实测 OOM。
   - **AF_PACKET 没有收包中断/adaptive 模式**：vpp-router 的 worker 空闲补丁是通用的，但 AF_PACKET 没有收包中断/唤醒源，默认会有一个核长期 100% 轮询，带来功耗、温度和风扇噪音问题。
4. **收益判断**：H5000M 的主要流量来自 WiFi 和 5G 模组，二者都绕不开 Linux；VPP 能显著加速的只是“有线 WAN ↔ LAN”这一小段。相比现有内核转发 + MediaTek 硬件加速，VPP 在本机上的性能收益有限、风险较高。
5. **推荐路线**：
   - **首选（低风险、快收益）**：先移植 vpp-router 的 **Gate 策略路由、DNS 分流、管理面板思路** 到 OpenWrt（nftables/ip rule 作为后端），不引入 VPP 数据面；默认固件保持内核转发与硬件加速。
   - **次选（如果必须跑 VPP）**：采用 **混合架构 B**——VPP 只接管 WAN（有线 WAN + 5G `wwan0`），LAN/WiFi 留在 Linux，TAP 互联；VPP 做 NAT/策略路由，Linux 做 WiFi、模组控制、LuCI 和管理。**不建议 A（VPP 全接管 + WiFi 经 TAP）作为默认固件**。
   - **P0 必须先验证**：musl 交叉编译、1GB 内存、AF_PACKET 吞吐、空闲 CPU/温度、procd 回退。任何一项不达标，就退回控制面方案。

> 本报告只做方案与可行性分析，不修改现有固件行为。所有“预计/需实测”项均需在真机 P0 阶段确认。

---

## 1. 任务与范围

### 1.1 目标

把 vpp-router 的核心能力（VPP 数据面、NAT44-EI、按域名/目的网段分流、WireGuard/IPsec、管理面板）适配到 H5000M 的 ImmortalWrt 固件体系，产出可构建、可安装、可回退的方案。

### 1.2 本阶段范围

- 源码与架构分析；
- 目标硬件/系统约束分析；
- 组件级可移植性评估；
- 数据面接入方式对比；
- 分阶段实施方案、验收门槛、测试计划、风险登记；
- 对本仓库（CI、Config、Scripts、docs）的落地清单。

### 1.3 不在本阶段范围

- 不提交 VPP/DPDK 源码或二进制；
- 不修改默认固件数据面；
- 不做性能承诺；
- 不处理 PPPoE（vpp-router 安装器明确不支持 PPPoE）；
- 不在本阶段实现 IPsec/strongSwan 全量适配。

---

## 2. 源项目解析

### 2.1 定位

vpp-router 是一个“VPP + DPDK 软路由”的完整工程：VPP 负责转发，Linux 负责编排；Gate 解析 DNS，按目的域名/IP 决定出口；附带安装器、管理面板、部署模块、补丁、压测工具。

- 基线：**VPP 26.06 + DPDK 26.03**；
- 目标发行版：**Debian/Ubuntu（apt）或 Fedora/RHEL（dnf）**，systemd 管理；
- 支持架构：x86_64、aarch64（aarch64 只编通用版本，不编服务器 CPU 变体）；
- 许可：Apache-2.0（例外：RTL8125 DPDK 补丁随原文件 BSD-3-Clause；uPlot MIT；strongSwan 插件产物需遵守 GPL-2.0-or-later）。

### 2.2 架构

```text
                 ┌──────────────── Linux（Debian/Ubuntu）────────────────┐
                 │  vpp-monitor / vpp-interfaces / vpp-firewall ...      │
                 │  Gate（vpp-egress-gate）  dnsmasq  sing-box  strongSwan│
                 │            │ VPP Binary API / CLI / nft                │
                 └────────────┼──────────────────────────────────────────┘
                              │
      ┌───────────────────────┴────────────────────────┐
      │                    VPP                         │
      │  NAT44-EI  ACL/ABF  WireGuard  IPsec  TAP      │
      │  DPDK PMD（服务器网卡） / AF_PACKET（家用网卡） │
      └───────┬───────────────────────────┬────────────┘
              │                           │
        PCIe 网卡（DPDK）            物理网口（AF_PACKET）
```

关键设计：

- **VPP 独占数据面**：接管网卡后，Linux 的 `ip/nft/uci` 看不到这些网口；DHCP、DNS、管理流量通过 TAP 回 Linux。
- **配置不持久**：VPP 启动时执行一份 CLI 文件；运行中改的地址/NAT/ACL/路由在 VPP 重启后丢失，由面板/服务重新下发。
- **Gate 的“先下发路由、再放行 DNS 应答”**：域名命中规则时，先通过 VPP API 写入目的地址路由，生效后才返回 DNS 应答；失败返回 SERVFAIL。

### 2.3 代码与组件规模

| 组件 | 规模/内容 | 说明 |
|:---|:---|:---|
| VPP 补丁 | 36 个 `.patch`（`patches/vpp`） | NAT44-EI 批量/修复、ACL 缓存、FIB 路径复制、WireGuard/IPv6 ND/RA、worker 休眠、mlx4 中断、多口命名等 |
| DPDK 补丁 | 2 个（`patches/dpdk`） | r8169 收包中断/多队列 |
| 树外插件 | 6 个目录 | NAPT66、NAT 映射域（nat-ei-context）、DNS 拦截、WireGuard/NAT 顺序、IPsec IKE punt、strongSwan VPP 后端 |
| 安装器 | `deploy/install/vpp-router-install.sh` 约 3440 行 bash | 检测、选网卡、编译 DPDK/VPP、生成 systemd 单元、可选 Gate/dnsmasq/IPsec/sing-box |
| 部署 Python | 约 7900 行 | 防火墙、IPv6、IPsec、DNS 分流、代理、迁移安装等 |
| 管理工具（Go） | 8 个模块，约 61000 行 | vpp-monitor、vpp-interfaces、vpp-firewall、vpp-wireguard、vpp-system、vpp-proxy、gate-admin、vpp-egress-gate；全部 `CGO_ENABLED=0` |
| 树外插件 C | 约 2000 行 | NAPT66、DNS 拦截、NAT context 等 |
| 平台适配 | `platforms/*` | RTL8125 非一致性 DMA PMD、RK3588 DDR、Phicomm N1 DWMAC 原生 PMD |

### 2.4 构建与运行模型（对移植最关键的几点）

- VPP 使用 CMake + Ninja，最小插件集为：
  `dpdk, af_packet, tap, nat/nat44_ei, wireguard, acl, abf, dhcp, mss_clamp, ping, ipsec_ike_punt, vxlan, gre`（按需增减）。
- DPDK 以静态库编译，`--whole-archive` 链进 VPP 的 dpdk 插件；小内存机器只编所选网卡的 PMD。
- 安装器依赖：`apt/dnf`、bash 4、systemd、`libnuma-dev`、`libssl-dev`、`libsystemd-dev`、`libunwind-dev`、`uuid-dev`、`patchelf`、`systemd-coredump`、`ethtool`、`iproute2`。
- 小内存策略：RAM < 3000MB 时 `main-heap-size 512M`、`buffers-per-numa 16384`；更小的 N1（1.8GB）只能单线程、不用大页。
- AF_PACKET 路径（无 DPDK 驱动的网卡）由 VPP 的 `af_packet` 插件提供 `create host-interface name <ifname>`；安装器会：
  - 让 NetworkManager 不管理该网口；
  - `ip addr flush`；
  - 关闭 GRO；
  - 打开 promisc；
  - `ip link set up`。
- **AF_PACKET 没有 rx-mode interrupt/adaptive 选项**；vpp-router 的 worker 空闲补丁与 DPDK 收包中断配套，不能直接让 AF_PACKET 在空闲时休眠。

### 2.5 功能清单（可移植性视角）

| 能力 | 实现 | 对 H5000M 的价值 | 移植难度 |
|:---|:---|:---|:---|
| NAT44-EI / NAT44-ED | VPP 插件 | 高（大会话 NAT、全锥形） | 中 |
| 按域名/目的网段分流 | Gate + VPP FIB/ABF/ACL | 高（核心卖点） | 中 |
| Fake-IP | Gate + sing-box | 高 | 中 |
| 端口转发/防火墙 | VPP ACL + 面板 | 中 | 中 |
| WireGuard | VPP 插件 + 面板 | 中（与内核 WG 冲突） | 中 |
| IPsec | strongSwan + VPP 后端 | 低/中 | 高 |
| IPv6 PD/RA/NAPT66 | Linux + VPP | 高（5G IPv6） | 高 |
| 管理面板 | Go 静态程序 | 中（与 LuCI 重复） | 低/中 |
| dnsmasq/DHCP | Linux | 高 | 低（需与 OpenWrt 集成） |
| 单臂 VLAN / 多网卡 | VPP | 中 | 低 |

### 2.6 许可证

- vpp-router：Apache-2.0；VPP：Apache-2.0；DPDK：BSD-3-Clause。
- strongSwan：GPL-2.0-or-later；sing-box：GPL-3.0（以实际版本为准）。
- 本仓库根 `LICENSE` 为 MIT，README 徽章写 GPL-3.0，二者不一致；引入 GPL 组件时，分发固件需同时满足相应许可证（提供源码/许可声明）。本报告不改变现有许可策略，只提示在 P4 做一次许可证清单审计。

---

## 3. 目标平台解析

### 3.1 硬件事实（以设备树与厂商规格为准）

| 项目 | 事实 | 证据 |
|:---|:---|:---|
| SoC | MediaTek MT7987A（Filogic），4×Cortex-A53 2.4GHz | 设备树 `compatible = "hiveton,h5000m", "mediatek,mt7987a"`；厂商页面 |
| 内存 | 厂商规格 1GB DDR4；设备树 `mt7987a.dtsi` 默认 memory 为 256MB | `mt7987a.dtsi` 的 `memory { reg = <0 0x40000000 0 0x10000000>; }`；需实机 `/proc/meminfo` 确认 U-Boot 是否修正为 1GB |
| 存储 | 8GB eMMC（8-bit，non-removable） | `&mmc0` 节点 |
| 有线网口 | 2×2.5G：gmac0 + RTL8221B（eth0），gmac1 + 内置 2.5G PHY（eth1） | `&gmac0`/`&gmac1`、`&mdio` |
| WiFi | MT7992（WiFi7 BE5040M），PCIe0；Linux 侧由 `kmod-mt7996e`/`mt7992-23-firmware` 驱动 | `&pcie0` 下 `mt7992@0,0`；`filogic.mk` 的 `DEVICE_PACKAGES` |
| 5G 模组 | MT5700M，USB3；Linux 侧 QMI/MBIM + USB serial | `&ssusb`、`&tphyu3port0`；`Config/GENERAL.txt` 的 `kmod-usb-net-qmi-wwan`、`kmod-usb-net-cdc-mbim` |
| 风扇 | PWM 风扇（pwm1），已有风扇控制插件 | `&fan`、`Config/GENERAL.txt` |

> 注意：仓库 README 写“MT7996E”，设备树实际为 `mt7992`；两者同属 mt76 驱动族，但报告以设备树为准。内存的 256MB 默认值必须实机确认，因为这直接决定 VPP 是否可运行。

### 3.2 软件栈事实

| 项目 | 事实 | 对移植的影响 |
|:---|:---|:---|
| 发行版 | ImmortalWrt（VIKINGYFY/immortalwrt `owrt`） | 与 Debian 目录结构、包管理、服务模型不同 |
| libc | musl | VPP/DPDK 官方主要验证 glibc；需要交叉编译验证与少量补丁 |
| init | procd + `/etc/init.d` + UCI | 不能使用 systemd 单元、`systemctl`、`journalctl`、`systemd-run` |
| 网络管理 | netifd + UCI + fw4 + dnsmasq/odhcpd | VPP 接管的网口必须从 netifd/fw4 中“摘出来”，否则双栈/双 DHCP 冲突 |
| 内核 | Linux 6.18 | 通用配置中 `CONFIG_PACKET=y`、`CONFIG_BPF_SYSCALL=y`；`HUGETLBFS`、`XDP_SOCKETS`、`VFIO`、`UIO`、`NUMA` 未启用 |
| 包管理 | opkg/apk | VPP/DPDK 不在 OpenWrt 官方 feed 中，需要自建包 |
| 构建 | OpenWrt buildroot / SDK，交叉编译 | VPP 的 CMake 交叉编译需要独立验证 |
| 现有组件 | sing-box（homeproxy）、kmod-wireguard、kmod-tun、kmod-veth、nftables、dnsmasq、Python3（构建期） | 可复用；但 VPP 模式会与内核 WG、fw4、dnsmasq 的所有权冲突 |

### 3.3 现有固件的数据面与配套

- 默认数据面：Linux 内核转发 + MediaTek 以太网驱动 + WiFi 驱动；若启用了 PPE/HNAT/WED 硬件加速，局域网↔WAN 和 WiFi 流量可绕过 CPU。
- 5G 模组插件：`luci-app-mt5700`（Rust/Tokio）或 `luci-app-mt5700m`（C 传输程序），负责 AT/QMI、拨号、APN、IPv6、信号/温度等；两者都独占 AT 串口。
- 网络模式插件：`luci-app-h5000m-netmode` 通过调整 `wan` 与模组承载接口的 metric 实现“有线优先/5G 优先/仅有线/仅 5G”。
- 风扇控制：读取 SoC/模组温度，PWM 调速；与 VPP 的 CPU 占用/温度直接相关。
- 在线升级：`luci-app-online-upgrade`，依赖固件产物命名与 Release 元数据。

### 3.4 关键约束总结

1. **不能把 VPP 当成“另一个软件包”直接塞进默认固件**：它会改变数据面所有权，影响 netifd、fw4、dnsmasq、LuCI、模组插件、netmode、在线升级和故障恢复。
2. **不能假设 DPDK 可用**：MT7987 的以太网是 SoC 平台设备，DPDK 主线没有对应 PMD；WiFi 是 PCIe，但 DPDK 没有 mt76 驱动。
3. **不能假设内存充足**：1GB 是硬约束；VPP 的默认堆/缓冲区策略需要重调。
4. **不能假设 systemd**：vpp-router 的安装、服务、日志、回退、定时器都要改成 procd/UCI/hotplug。
5. **不能假设“VPP 一定比内核快”**：在本机上，WiFi/模组是内核路径，AF_PACKET 有拷贝开销，且没有硬件 NAT 卸载；必须实测对比。

---

## 4. 可行性评估

### 4.1 组件级总表

| 组件 | 可移植性 | 主要工作 | 风险 | 结论 |
|:---|:---|:---|:---|:---|
| VPP 核心（无 DPDK，仅 af_packet/tap/nat/acl/abf/dhcp/wireguard） | 中 | musl 交叉编译、最小插件、`-Werror`/依赖补丁、启动参数 | 高 | P0 必须验证 |
| DPDK | 低（对本机） | 无 MTK PMD；仅为未来 AF_XDP/原生 PMD 保留 | 高 | 第一阶段不引入 |
| VPP 补丁系列（36 个） | 中 | 26.06 基线可直接用；删掉 r8169/mlx4/RK3588/N1 相关；补 musl/构建补丁 | 中 | 可复用大部分功能补丁 |
| 树外插件 | 中 | CMake 集成、依赖、OpenWrt 打包 | 中 | NAPT66/DNS 拦截等按需启用 |
| 安装器（3440 行 bash） | 低 | 整体重写为 OpenWrt 包 + procd + UCI | 高 | 不复用 |
| Go 管理工具（8 个模块） | 高 | `CGO_ENABLED=0` 静态二进制可直接跑；改 procd、路径、日志、权限 | 低/中 | 可复用 |
| Gate | 高 | Go 程序可复用；`install.py` 的 systemd 安装改 procd；nft 规则适配 | 中 | 可复用，核心价值 |
| Python 部署模块 | 中 | systemd/nft/VPP API/netns 适配；体积与 Python 运行时 | 中 | 按需移植，能砍则砍 |
| strongSwan/IPsec | 低 | OpenWrt strongSwan 6.0.7 与源补丁 6.0.4 需 rebase；VPP 插件构建 | 高 | 放 P2/P3 |
| dnsmasq/DHCP | 高 | 与 OpenWrt dnsmasq 集成，不另起一套 | 低/中 | 可复用 |
| IPv6 PD/RA/NAPT66 | 中 | VPP 接管 WAN 后，PD 客户端/RA 的归属要重设计 | 高 | P2 |
| 管理面板 vs LuCI | 中 | 两套管理面并存；或写 LuCI 页面调用 VPP API | 中 | 先并存，后融合 |
| CI/构建 | 中 | 新配置、交叉编译、缓存、产物命名、测试 | 中 | 必须新增独立流水线 |

### 4.2 数据面接入方式对比

| 方式 | 是否需要 DPDK | 对 MT7987 可用性 | 性能预期 | 空闲功耗 | 开发成本 | 结论 |
|:---|:---|:---|:---|:---|:---|:---|
| DPDK 原生 PMD | 是 | **不可用**（DPDK 主线无 MediaTek 以太网 PMD） | 最高 | 可中断（需补丁） | 极大（自研 PMD） | 不选 |
| VPP `af_packet` 插件 | 否 | **可用**（物理网口 + PACKET_MMAP） | 中等，单核约数百 kpps 量级，需实测 | 默认轮询，单核 100% | 低 | **P0/P1 采用** |
| DPDK AF_PACKET PMD | 是 | 可用，但还是要 DPDK 构建 | 与 VPP af_packet 相近 | 轮询 | 中 | 不如直接用 VPP 插件 |
| AF_XDP（VPP `af_xdp` 插件） | 是（libxdp/libbpf） | 取决于 mtk_eth_soc 的 XDP zero-copy 支持；内核未开 `XDP_SOCKETS` | 高于 AF_PACKET（若 zero-copy） | 可中断 | 高（需打包 libxdp/libbpf、验证驱动） | P3 评估 |
| 自研 `mtk_eth_soc` 原生 PMD + 内核 helper | 是 | 理论可行（参考 N1 DWMAC） | 最高 | 可中断 | 极高（DMA/多队列/PHY/PPE 复杂） | 不建议 |

**结论**：第一阶段只用 VPP `af_packet` + `tap`，**不编 DPDK**。这样能绕开 DPDK 交叉编译、libnuma、IOMMU/UIO、大页等全部问题，把 P0 的变量降到最少。

### 4.3 构建与依赖专项

已验证/已确认的事实：

- VPP 源码对 musl 已有少量适配：`src/vppinfra/socket.c` 对 `IPPORT_USERRESERVED` 做了 `#ifndef __GLIBC__`；`src/vppinfra/mem_intercept.c` 对非 glibc 用 `dlsym(RTLD_NEXT, ...)`。这说明 musl 构建**有希望**，但不是官方支持矩阵。
- VPP 的 `src/CMakeLists.txt` 硬编码 `-g -Werror -Wall`；musl 头文件差异可能触发警告并导致构建失败，需要补丁或改编译选项。
- VPP 源码中**没有发现 systemd/sd_notify/libsystemd 的直接使用**；`libsystemd-dev` 是 vpp-router 安装器的依赖项，移植时可剥离。
- `libnuma` 只在 VPP 的 **dpdk 插件** CMake 中强制查找；找不到时整个 dpdk 插件会被禁用。**不编 dpdk 插件就不需要 libnuma**。
- `libunwind` 是 VPP 构建的硬依赖（vpp-router 安装器在找不到时直接失败）；OpenWrt 主仓库有 `package/libs/libunwind`，可用。
- OpenWrt 主仓库有 `libbpf`、`openssl`、`nftables`；packages feed 有 `strongswan 6.0.7`、`libarchive`。**没有** `numactl`、`libxdp`、`vpp`、`dpdk` 包。
- DPDK 主线 `drivers/net` 中没有 MediaTek PMD；只有 r8169 等。H5000M 的 `mtk_eth_soc` 不在 DPDK 支持列表。
- Alpine 有 `dpdk` 包但没有 `vpp` 包；OpenWrt 两者都没有 → **VPP 的 OpenWrt 打包需要从零建立**。

需要新增/验证的构建补丁（P0 产出）：

1. `-Werror` 在 musl/新编译器下的告警处理（建议新增 `-Wno-error` 或按告警逐项修）。
2. `libnuma` 可选化（仅在启用 dpdk 插件时需要；第一阶段直接不编 dpdk）。
3. `libsystemd`/systemd 相关可选依赖剥离（确认 CMake 不引用）。
4. OpenWrt 安装布局：`/usr/sbin/vpp`、`/usr/lib/vpp_plugins`、`/usr/share/vpp/api`、`/etc/vpp`、`/run/vpp`。
5. 启动参数：`unix { nodaemon runtime-dir /run/vpp cli-listen /run/vpp/cli.sock }`、`socksvr`、`statseg`、`memory { main-heap-size 256M }`、`buffers { buffers-per-numa 8192 }`、`cpu { main-core ... }`、`plugins { plugin default { disable } ... }`。
6. 如果未来启用 DPDK：`no-hugetlb`、`no-pci`、`iova-mode va`、静态最小 PMD。

### 4.4 资源专项

| 资源 | 事实/预算 | 风险与对策 |
|:---|:---|:---|
| 内存 | 1GB；OpenWrt 基线 + WiFi + 模组 + 面板 + VPP | VPP 堆建议 192–256MB，buffers 8192（约 16MB）；不开大页；开 zram 作为兜底；P0 实测 RSS/OOM |
| 磁盘 | 8GB eMMC | VPP + 插件 + Go 工具预计几十到数百 MB；容量足够，但需确认 rootfs/overlay 分区大小 |
| CPU | 4×A53 2.4GHz | VPP 主线程绑一个核；WiFi/模组 IRQ 绑到其他核；不开多 worker（AF_PACKET 单队列收益低） |
| 空闲 CPU | AF_PACKET 默认轮询 | 一个核长期 100%；需要新增 af_packet 的 poll/eventfd 休眠，或接受功耗/温度代价 |
| 温度/风扇 | 已有 PWM 风扇控制 | VPP 满载会抬高 SoC 温度；需把风扇曲线与 VPP 模式联动，P0 记录温度/转速/噪音 |
| 启动时间 | procd 启动 VPP + TAP + 服务 | 需保证 30 秒内恢复网络；失败自动回退 Linux 数据面 |

> 说明：vpp-router 在 RAM < 3000MB 时默认 512MB 堆 + 16384 buffers。对 1GB 设备，这个默认值本身就会导致内存紧张，必须重调，不能照搬。

### 4.5 网络集成专项

#### 4.5.1 WiFi

- MT7992 是 PCIe WiFi，Linux `mt76` 驱动管理；VPP 没有 WiFi 驱动，**不能直接接管 WiFi**。
- 方案：WiFi 留在 Linux，桥接到 `br-lan`；VPP 与 `br-lan` 之间用 TAP（或 veth）互联。WiFi→WAN 的流量路径为：
  `WiFi → mac80211 → br-lan → TAP → VPP NAT → WAN`。
- 代价：失去 WiFi 硬件加速/WED；多一次 TAP 拷贝；CPU 占用上升；WiFi 吞吐可能下降。
- 如果 VPP 全接管两个以太网口，WiFi 仍要经 TAP 回注；LAN 口本身可以由 VPP 桥接，但 WiFi 仍是 Linux。

#### 4.5.2 5G 模组

- MT5700M 通过 USB 提供 QMI/MBIM 网络接口（通常 `wwan0`）和 AT 串口；数据面是 L3 点对点，不适合简单桥接。
- 两种选择：
  - **VPP 接管 `wwan0`（AF_PACKET）**：VPP 跑 DHCP 客户端；模组插件只做 AT/QMI 控制和链路监测，不再写路由/DNS。需要改模组插件（外部仓库）以支持“VPP 模式”。
  - **Linux 保留 `wwan0`**：VPP 通过 TAP/veth 与 Linux 做 L3 转发；需要策略路由和双重 NAT/转发，复杂度高，性能差。
- 建议：若走 VPP，选择第一种，并明确“数据面所有权”边界；否则 5G 路径保持 Linux。

#### 4.5.3 netifd/fw4/LuCI

- VPP 接管的网口必须：
  - 在 UCI 中设为 `proto 'none'`、`auto '0'`，不让 netifd 配地址/DHCP；
  - 从 `br-lan`、防火墙 zone、dnsmasq/odhcpd 的接口列表中移除；
  - 关闭 IPv6（`disable_ipv6=1`）、ARP/ND 响应，避免内核与 VPP 双栈；
  - 在 LuCI 中隐藏或标记为“由 VPP 管理”。
- 否则会出现：内核 DHCP 与 VPP DHCP 抢地址、内核 ICMP/RST 泄漏、fw4 规则误伤、LuCI 显示错误。

#### 4.5.4 netmode

- 现有 `luci-app-h5000m-netmode` 通过 Linux 路由 metric 切换“有线/5G 优先”。
- VPP 模式下 metric 无意义，需要：
  - 由一个小控制器把模式翻译成 VPP 默认路由（FIB）切换；
  - 或在 Gate 中实现出口优先级；
  - UI 保持现有四种模式，但后端改为 VPP API。
- 这是跨仓库改动（netmode 插件），需在 P2 排期。

#### 4.5.5 IPv6

- VPP 的 NAT44 只做 IPv4；IPv6 需要 NAPT66 插件（源项目有）或 Linux 侧处理。
- 5G 网络通常依赖 IPv6 PD/RA；vpp-router 的 IPv6-PD 是 Linux 侧 `pd-sync` + TAP，不是 VPP 原生。
- 若 VPP 接管 WAN，DHCPv6-PD 客户端、RA、防火墙的归属需要重新设计；这是 P2 的高风险项，不建议首版承诺。

#### 4.5.6 硬件加速

- 若当前固件启用 MediaTek PPE/HNAT/WED，VPP 接管后会绕过这些加速；需要 P0 对比：
  - 内核转发（HNAT 开/关）vs VPP（AF_PACKET）；
  - 有线 2.5G、WiFi、5G 三种路径；
  - 大包/小包、单流/多流、NAT 会话数。
- 如果 VPP 在有线路径上没有明显优势，则本项目的产品价值需要重新评估。

### 4.6 管理面专项

| vpp-router | OpenWrt 对应 | 改造 |
|:---|:---|:---|
| systemd 单元 | procd `/etc/init.d/*` | 重写所有服务单元；`respawn`、`pidfile`、日志转 syslog |
| `systemctl`/`journalctl` | `ubus`/`logread` | 面板/脚本中的服务管理调用替换 |
| apt/dnf 安装 | opkg/apk 包 | 拆包：vpp、plugins、tools、luci-app、gate |
| `/usr/local` 布局 | `/usr/sbin`、`/usr/lib`、`/etc/config` | 统一 OpenWrt 路径；配置进 UCI |
| NetworkManager | netifd/UCI | 网口所有权、unmanaged、hotplug |
| `systemd-run` 回退定时器 | procd + 脚本/定时器 | 实现健康检查与自动回退 |
| `systemd-coredump` | `kernel.core_pattern`/`ulimit` | 简化；避免 core 占满 eMMC |
| dnsmasq.service | OpenWrt dnsmasq | 不另起服务；用 UCI 生成配置 |
| 独立 HTTPS 面板 | LuCI + 可选面板 | 先并存（9480），再评估是否写 LuCI 页面 |

Go 工具的优势：全部 `CGO_ENABLED=0`，静态链接，可直接在 musl/OpenWrt 运行；主要改启动参数、路径、日志、权限和 procd 单元。

### 4.7 回退与安全专项

- **管理通道**：如果 VPP 接管两个以太网口，SSH 可能随 VPP 故障一起消失。必须保留：
  - WiFi 管理（LAN 留在 Linux 时天然可用）；
  - 串口/UART（设备有 `serial0`）；
  - 或自动回退：VPP 启动后 60 秒内未通过健康检查，停止 VPP、恢复 netifd 配置、重启网络。
- **健康检查**：`vppctl show interface`、WAN 网关 ping、DNS 查询、TAP 状态；任一失败触发回退。
- **配置持久化**：UCI 保存“上次可用配置”；启动失败计数；连续失败则默认走 Linux 数据面。
- **安全**：
  - VPP API/CLI socket 仅 root 可访问；
  - 面板 TLS 自签证书 + 强密码；不要默认弱口令；
  - 不把 VPP API 暴露到 WAN；
  - 防火墙规则由 VPP ACL 与 fw4 各管一段，避免双写；
  - 报告中不出现真实 IP/密钥/令牌（本报告全部使用文档示例地址）。

### 4.8 可行性结论

- **VPP 核心跑起来**：可行，前提是 P0 通过 musl 交叉编译与 1GB 内存验证。
- **完整功能对齐**：难度高，主要卡在 WiFi/5G 所有权、IPv6 PD、netmode、LuCI/fw4 集成、IPsec。
- **默认固件直接切换**：不建议；应采用“可选模式/独立固件变体 + 自动回退”。
- **最大不确定性**：AF_PACKET 的实际吞吐与空闲功耗；只有真机数据能决定 VPP 是否值得作为默认数据面。

---

## 5. 方案选项

### 5.1 方案 A：VPP 全接管

```text
WiFi(MT7992) ── kernel ── br-lan ── TAP ─┐
LAN 2.5G ─────────────── AF_PACKET ──────┼── VPP ── NAT/策略 ── AF_PACKET ── WAN 2.5G
5G wwan0 ─────────────── AF_PACKET ──────┘
```

- VPP 接管两个以太网口和 `wwan0`；WiFi 经 TAP 回注。
- 优点：数据面统一，Gate/NAT/策略路由完整；有线 LAN↔WAN 可走 VPP 内部桥。
- 缺点：1GB 内存压力最大；WiFi 失去硬件加速；模组插件/netmode/LuCI/fw4 冲突最多；故障影响面最大。
- 结论：**只作为实验/技术验证，不作为默认固件**。

### 5.2 方案 B：VPP 混合（推荐，如果必须上 VPP）

```text
WiFi(MT7992) ── kernel ── br-lan ── TAP ─┐
LAN 2.5G ─────────────── kernel ─────────┘
                                          ├── VPP（WAN 侧）── NAT/策略 ── AF_PACKET ── WAN 2.5G
5G wwan0 ───────────────── AF_PACKET ─────┘
```

- VPP 只接管 WAN（有线 WAN + `wwan0`）；LAN/WiFi 留在 Linux；TAP 连接 `br-lan` 与 VPP。
- 优点：保留 WiFi 驱动、LAN 交换、LuCI 管理、模组控制；VPP 负责 NAT/策略路由；故障时 LAN 仍在。
- 缺点：LAN→WAN 经 TAP，失去 HNAT；有线 2.5G 性能可能不如内核；仍需改 netmode/模组插件。
- 结论：**如果目标是“让 VPP 真正承载 NAT/分流”，这是风险最低的形态**。

### 5.3 方案 C：控制面移植（首选，低风险）

- 不引入 VPP；把 Gate 的规则模型、DNS 分流、面板思路移植到 OpenWrt：
  - DNS 应答 → 写入 nftables set / ip rule / 路由表；
  - 按域名/目的网段/设备分流到 WireGuard、sing-box（TPROXY）、直连；
  - LuCI 页面管理规则；
  - 保留内核转发 + HNAT + WiFi 加速。
- 优点：不改变数据面、不影响现有固件稳定性、开发量小、可立即交付用户价值。
- 缺点：不是 VPP；没有 NAT44-EI 的大会话表；没有 VPP WireGuard/IPsec 加速；性能模型不同。
- 结论：**推荐作为第一阶段产品化路线**；后续再把 VPP 作为可选实验包。

### 5.4 方案对比

| 维度 | A 全接管 | B 混合 | C 控制面 |
|:---|:---|:---|:---|
| VPP 数据面 | 全部 | 仅 WAN | 无 |
| WiFi 性能/加速 | 受影响 | 保留 | 保留 |
| 5G 模组兼容 | 需改插件 | 需改插件 | 不变 |
| 内存风险 | 最高 | 中高 | 低 |
| 空闲功耗 | 高（轮询） | 中高 | 低 |
| 故障影响 | 大 | 中 | 小 |
| 功能收益 | 最高 | 中高 | 中 |
| 开发量 | 最大 | 大 | 中 |
| 推荐度 | 低（实验） | 中（VPP 路线） | **高（首选）** |

---

## 6. 推荐实施路线

### P0：可行性验证（不改默认固件）

目标：用最小变量回答“VPP 能否在 H5000M 上稳定跑、内存/CPU/吞吐是否可接受”。

工作项：

1. 用 OpenWrt SDK（aarch64_cortex-a53，musl）交叉编译 **VPP 26.06 最小集**：
   - 插件：`af_packet, tap, nat44_ei, acl, abf, dhcp, wireguard, ping, mss_clamp`；
   - **不编 DPDK**，不编 IPsec，不编 strongSwan；
   - 处理 `-Werror`、musl 头文件、`libunwind` 依赖；
   - 产出 `.ipk` 或可直接安装的根目录包。
2. 在 H5000M 上手工运行：
   - `create host-interface name eth1`（先拿一个口做实验，不接管管理口）；
   - 创建 TAP，配置 NAT44-EI；
   - 从另一台机器打流/iperf；
   - 记录 `vppctl show interface/errors`、`/proc/meminfo`、`top`、温度、风扇转速。
3. 验证共存：
   - netifd 不管实验口；
   - 内核不响应 ARP/ND；
   - WiFi、5G、LuCI、风扇、在线升级不受影响；
   - 停止 VPP 后网口能还给内核。
4. 输出 P0 报告与 go/no-go 结论。

**P0 建议验收门槛（可按实际调整）**：

| 指标 | 门槛 |
|:---|:---|
| 编译 | VPP 最小集在 OpenWrt SDK 下构建成功，产物可在目标机启动 |
| 内存 | VPP RSS ≤ 250MB；系统剩余可用内存 ≥ 150MB；24h 无 OOM |
| 转发 | 1500B NAT ≥ 1.0Gbps；64B ≥ 250kpps；丢包 < 0.1% |
| 空闲 | 可接受单核 100%（需记录温度）；或实现 AF_PACKET 休眠后 ≤ 10% |
| 稳定性 | 72h 无崩溃；VPP 被杀后 60s 内回退可用 |
| 温度 | 满载温度/风扇转速在现有风扇曲线可控范围内 |

### P1：最小可用 VPP 包（有线 WAN + LAN TAP）

- 建立独立包仓库（建议 `LianXia233/openwrt-vpp-router`），拆分：
  - `vpp`（核心 + 最小插件）；
  - `vpp-router-tools`（Go 静态二进制）；
  - `luci-app-vpp-router`（UCI + 状态页 + 基本配置）；
  - `vpp-egress-gate`（可选）。
- procd 服务、UCI 配置、首次启动、健康检查、自动回退。
- 只支持 IPv4 NAT + DHCP WAN + LAN TAP；IPv6、Gate、WireGuard、IPsec 暂不做。
- 独立 CI 流水线构建包；默认两套固件不变。

### P2：功能对齐

- Gate：域名/IP/设备分流、Fake-IP、DNS 接管、TPROXY 到 sing-box。
- VPP WireGuard + NAT66；IPv6 PD/RA；端口转发/防火墙。
- netmode 与 5G 模组插件适配（数据面所有权切换）。
- 面板页面与 LuCI 融合/并存。
- IPsec/strongSwan（可选，单独评估）。

### P3：性能与功耗优化

- AF_XDP 或原生 `mtk_eth_soc` PMD 评估（仅在 P0/P1 数据证明 AF_PACKET 不够时）。
- AF_PACKET 空闲休眠/中断唤醒（poll/eventfd）。
- 多队列/RSS、IRQ 绑核、NAPI 共存。
- 热设计/风扇曲线/功耗对比。

### P4：产品化

- 独立固件变体或包 feed；在线升级；配置迁移。
- 文档、README、CHANGELOG、故障排查手册。
- 安全审计、许可证清单、脱敏检查。
- 发布矩阵与支持范围。

---

## 7. 详细工作分解（WBS）

| 编号 | 阶段 | 工作项 | 主要产出/改动 | 验收 |
|:---|:---|:---|:---|:---|
| P0-01 | P0 | OpenWrt SDK 交叉编译环境 | 构建脚本、toolchain 说明 | VPP 能 configure |
| P0-02 | P0 | VPP 最小集构建 | 插件裁剪、musl/`-Werror`/libunwind 补丁 | 生成可执行文件 + 插件 |
| P0-03 | P0 | 目标机运行 | 启动配置、af_packet/TAP/NAT CLI | `vppctl show interface` 正常 |
| P0-04 | P0 | 性能/资源测量 | 测试脚本、数据表 | 达到 P0 门槛或给出否决结论 |
| P0-05 | P0 | 共存/回退验证 | netifd 摘除、sysctl、恢复脚本 | 停止 VPP 后网络恢复 |
| P1-01 | P1 | 包仓库骨架 | `vpp/`、`tools/`、`luci-app/` Makefile | `make package/.../compile` 通过 |
| P1-02 | P1 | procd/UCI | `/etc/init.d/vpp-router`、`/etc/config/vpp_router` | 开机自启、UCI 生效 |
| P1-03 | P1 | 网络所有权 | UCI 默认配置、hotplug、fw4/dnsmasq 排除 | 无双 DHCP/双栈 |
| P1-04 | P1 | 健康检查/回退 | 60s 定时器、失败恢复、日志 | 注入故障可回退 |
| P1-05 | P1 | Go 工具打包 | 预编译 aarch64 静态二进制 | 面板/CLI 可运行 |
| P1-06 | P1 | CI 流水线 | 独立 workflow、缓存、产物 | 产出 `.ipk`/固件 |
| P1-07 | P1 | P1 测试 | 功能/稳定性/回归 | IPv4 NAT/DHCP/DNS + 24h |
| P2-01 | P2 | Gate 移植 | Go 程序 + procd + nft | 域名规则命中/失败 SERVFAIL |
| P2-02 | P2 | DNS 接管/TPROXY | nft 规则、sing-box 对接 | Fake-IP/TPROXY 可用 |
| P2-03 | P2 | WireGuard/NAT66 | VPP WG + 面板 | 握手/吞吐/重启恢复 |
| P2-04 | P2 | IPv6 PD/RA | pd 客户端、RA、防火墙 | 5G IPv6 可用 |
| P2-05 | P2 | netmode/模组适配 | 模式→VPP FIB、插件所有权 | 四种模式可切换 |
| P2-06 | P2 | 管理面 | LuCI 页面/面板 | 主要操作可完成 |
| P2-07 | P2 | IPsec（可选） | strongSwan 6.0.7 rebase | 单独验收 |
| P3-01 | P3 | AF_XDP/原生 PMD 评估 | PoC/数据 | 是否值得替换 AF_PACKET |
| P3-02 | P3 | 空闲休眠 | af_packet poll/eventfd | 空闲 CPU/温度下降 |
| P3-03 | P3 | 多队列/IRQ | 绑核、队列配置 | 多流吞吐提升 |
| P3-04 | P3 | 热/功耗 | 风扇曲线、对比报告 | 温度/噪音可接受 |
| P4-01 | P4 | OTA/升级 | 包版本、配置迁移 | 升级不砖 |
| P4-02 | P4 | 文档 | README/CHANGELOG/FAQ | 可维护 |
| P4-03 | P4 | 安全/许可 | 审计、SBOM、脱敏 | 合规 |
| P4-04 | P4 | 发布 | 固件/包 feed | 支持矩阵明确 |

---

## 8. 本仓库落地清单

> 原则：默认两套固件（MT5700/MT5700M）行为不变；VPP 作为独立配置/流水线/包仓库引入，失败不影响现有发布。

### 8.1 新增目录/文件

| 路径 | 作用 | 阶段 |
|:---|:---|:---|
| `docs/VPP-ROUTER-移植适配方案与可行性报告.md` | 本报告 | 已完成 |
| `Config/VPP.txt` | 可选 VPP 固件配置（默认不启用） | P1 |
| `docs/vpp/` | VPP 设计、测试、排障文档 | P1 |
| `Scripts/VppPreset.sh` | 生成 UCI 默认配置（端口、WAN/LAN、回退） | P1 |
| `files/etc/uci-defaults/9x-vpp-router` | 首启初始化、网口摘除、sysctl | P1 |
| `files/etc/init.d/vpp-router` 等 | procd 服务 | P1 |
| `.github/workflows/VPP-BUILD.yml` | 独立 VPP 包/固件流水线 | P1 |

### 8.2 需要修改的现有文件

| 文件 | 改动 | 注意 |
|:---|:---|:---|
| `Scripts/Packages.sh` | 条件克隆 VPP 包仓库（仅 `WRT_VPP=1`） | 不影响默认构建 |
| `.github/workflows/WRT-CORE.yml` | 可选交叉编译/安装 VPP 包；新增 smoke test | 默认路径不变 |
| `.github/workflows/WRT-BUILD.yml` | 新增 `VPP` 输入或独立 workflow | 避免每日构建翻倍 |
| `Config/GENERAL.txt` | 仅在 VPP 配置中追加依赖（不动默认） | 避免默认固件变大 |
| `README.md` | 新增“VPP 实验固件”章节 | P1 后 |
| `CHANGELOG.md` | 记录变更 | 按仓库规范 |

### 8.3 建议的包仓库结构（独立仓库）

```text
openwrt-vpp-router/
├── vpp/
│   ├── Makefile
│   ├── patches/            # musl、-Werror、OpenWrt 路径、可选依赖
│   └── files/
│       ├── vpp.init
│       └── startup.conf
├── vpp-router-tools/       # Go 静态二进制（CI 预编译）
├── vpp-egress-gate/
├── luci-app-vpp-router/
│   ├── Makefile
│   ├── root/etc/init.d/
│   ├── root/etc/config/vpp_router
│   ├── root/etc/uci-defaults/
│   ├── htdocs/luci-static/resources/view/vpp/
│   └── root/usr/share/rpcd/acl.d/
└── README.md
```

### 8.4 关键配置草案（仅示意，落地时细化）

UCI：

```uci
config vpp 'main'
    option enabled '0'
    option heap_mb '256'
    option buffers '8192'
    option workers '0'
    option wan_if 'eth1'
    option lan_tap 'vpp-lan'
    option rollback_timeout '60'

config nat 'nat'
    option mode 'ei'
    option ext_if 'wan'
```

procd（示意）：

```sh
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/vpp -c /etc/vpp/startup.conf
    procd_set_param respawn 3600 5 0
    procd_set_param file /etc/vpp/startup.conf
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
```

> 所有目标端脚本使用 POSIX sh/BusyBox ash 语法；文件必须 LF；路径通过变量/UCI 读取，禁止硬编码 `/home/...`、`/Users/...` 等系统路径。

### 8.5 CI 策略

- VPP 包单独构建、缓存、发布，不阻塞每日固件构建；
- Go 工具用 `GOOS=linux GOARCH=arm64 CGO_ENABLED=0` 预编译；
- 构建产物做静态检查：ELF 架构、musl 链接、插件清单、`sh -n`、`jq empty`、LF 检查；
- 真机运行测试放在 P0/P1 的独立流程，不放进每日 CI；
- 产物命名建议 `H5000M-MT5700-VPP-<日期>-sysupgrade.bin`，与默认两套区分。

---

## 9. 测试与验收计划

### 9.1 功能测试

| 类别 | 用例 | 通过标准 |
|:---|:---|:---|
| 启动 | 冷启动/重启 50 次 | 网络可用；VPP 状态正确；无内核 oops |
| IPv4 NAT | TCP/UDP/ICMP、端口转发、MTU/PMTU | 双向通；大包不分片错误 |
| DHCP/DNS | WAN DHCP、LAN DHCP、DNS 解析 | 租约正确；DNS 无泄漏 |
| Gate | 域名命中/未命中、路由下发失败、Fake-IP、VPP 重启 | SERVFAIL 正确；路由恢复 |
| WireGuard | 握手、重连、重启恢复 | 隧道可用；配置持久化 |
| IPv6 | PD、RA、NAPT66、防火墙 | 地址/前缀正确；入站受控 |
| netmode | 四种模式切换、断链倒换 | 切换生效；无环路/黑洞 |
| 模组 | 拨号、APN、IPv6、信号/温度、短信 | 原功能不回归 |
| WiFi | 2.4/5G、桥接、吞吐、漫游 | 不回归 |
| 管理面 | 面板登录/TLS/页面操作；LuCI | 操作生效；权限正确 |
| 风扇 | 温度联动、PWM | 不失控；噪音可接受 |
| 升级 | sysupgrade、保留配置、回滚 | 不砖；配置兼容 |

### 9.2 性能测试

- 有线：2.5G/1G，1500B/512B/64B，单流/多流，NAT 会话 1/1k/10k/100k；
- WiFi：2.4G/5G，近/中/远点，TCP/UDP；
- 5G：实际套餐/信号下行/上行；
- VPN：WireGuard、IPsec（若启用）；
- 资源：每核 CPU、RSS、温度、风扇转速、功耗；
- 对照：内核转发（HNAT 开/关）vs VPP（AF_PACKET）vs（可选）AF_XDP。

### 9.3 稳定性/故障注入

- 72h 满载/混合负载；
- kill VPP、kill Gate、删除 TAP、拔网线、断 5G、断电重启；
- 配置损坏/磁盘满/内存压力；
- 热插拔 WiFi/模组/USB；
- 回退时间、恢复后配置一致性。

### 9.4 安全测试

- 默认口令、TLS 证书、面板端口暴露；
- VPP API/CLI socket 权限；
- fw4 与 VPP ACL 的双写冲突；
- 日志/配置中无真实凭据；
- 许可证与源码提供。

---

## 10. 风险登记表

| 编号 | 风险 | 概率 | 影响 | 缓解/触发条件 |
|:---|:---|:---|:---|:---|
| R1 | VPP 在 musl 下编译失败或运行异常 | 中 | 高 | P0 先验证；保留 `-Wno-error`/补丁；失败则停止 VPP 路线 |
| R2 | 1GB 内存 OOM | 高 | 高 | 256MB 堆/8192 buffers/zram；P0 24h 压测；否则放弃 |
| R3 | AF_PACKET 吞吐不达标 | 中高 | 高 | P0 实测；备选 AF_XDP/原生 PMD；否则只做控制面 |
| R4 | 空闲单核 100% 导致高温/风扇噪音 | 高 | 中高 | 新增 poll/eventfd 休眠；风扇曲线；否则接受或不用 VPP |
| R5 | WiFi/5G 经 TAP 后性能下降 | 高 | 中高 | 混合架构 B；保留内核路径；实测对比 |
| R6 | netifd/fw4/dnsmasq 双写冲突 | 高 | 中高 | UCI 摘除、hotplug、LuCI 隐藏、启动顺序 |
| R7 | 模组插件与 VPP 抢 `wwan0` | 高 | 高 | 明确所有权；插件只做 AT/QMI；跨仓库改动 |
| R8 | netmode 与 VPP 路由不一致 | 高 | 中 | 重写为 VPP FIB 控制；UI 不变 |
| R9 | VPP 故障导致失联/变砖 | 中 | 高 | 60s 自动回退；保留 WiFi/串口管理；健康检查 |
| R10 | IPv6 PD/RA 不可用 | 中高 | 中高 | 首版不承诺 IPv6；P2 单独设计 |
| R11 | strongSwan 6.0.4→6.0.7 补丁不兼容 | 中 | 中 | 单独 rebase；IPsec 延后 |
| R12 | 许可证/分发合规 | 低 | 中 | P4 做 SBOM/许可清单；保留源码 |
| R13 | 在线升级破坏 VPP 配置/包 | 中 | 中 | 配置备份/迁移；包版本约束；回退 |
| R14 | 维护成本高（VPP 版本升级/补丁重放） | 高 | 中 | 固定版本；补丁集最小化；独立仓库 |

---

## 11. 待确认的决策点

1. **产品定位**：VPP 是默认数据面，还是仅作为可选实验包/独立固件？
2. **上行形态**：主要用 5G 还是有线 WAN？是否必须支持双上行自动切换？
3. **性能底线**：WiFi/HNAT 硬件加速是否必须保留？可接受的空闲功耗/温度上升是多少？
4. **功能优先级**：首版是否必须包含 IPv6 PD、WireGuard、IPsec、Gate 分流？
5. **管理面**：继续以 LuCI 为主，还是接受独立 Go 面板（9480）并存？
6. **发布方式**：第三个固件变体、独立包 feed，还是仅实验分支？
7. **回退策略**：VPP 启动失败是否自动回退 Linux 数据面？保留哪个管理通道（WiFi/串口/管理口）？

---

## 12. 附录

### 12.1 关键证据

- vpp-router README：明确要求 Debian/Ubuntu 或 Fedora、systemd、apt/dnf；小内存 <3GB 时 `main-heap-size 512M`；AF_PACKET 用于无 DPDK 驱动的网卡；PPPoE 不在安装器范围。
- `deploy/install/vpp-router-install.sh`：依赖 `libnuma-dev`、`libssl-dev`、`libsystemd-dev`、`libunwind-dev`、`uuid-dev`、`patchelf`、`systemd-coredump`；使用 `systemctl`、`systemd-run`、NetworkManager；AF_PACKET 路径会 flush 地址、关 GRO、开 promisc。
- VPP 源码：`src/vppinfra/socket.c` 有 musl 的 `IPPORT_USERRESERVED` 适配；`src/vppinfra/mem_intercept.c` 对非 glibc 用 `dlsym`；`src/CMakeLists.txt` 硬编码 `-Werror`；`src/plugins/dpdk/CMakeLists.txt` 强制查找 `libnuma`；未发现 systemd 直接依赖。
- VPP `af_packet` 插件：`create host-interface name <ifname> [num-rx-queues ...] [num-tx-queues ...]`；FEATURE.yaml 标注 production；CLI 没有 rx-mode interrupt/adaptive 选项。
- DPDK 主线 `drivers/net` 列表中没有 MediaTek PMD；`drivers/net/mtk` 不存在。
- H5000M 设备树：`target/linux/mediatek/dts/mt7987a-hiveton-h5000m.dts`；`mt7987a.dtsi` 的 memory 默认 256MB；`filogic.mk` 的 `Device/hiveton_h5000m`。
- 厂商规格：Hiveton H5000M，MT7987A 4×A53 2.4GHz、DDR4 1GB、eMMC 8GB、2×2.5G、WiFi7 BE5040M。
- OpenWrt 包可用性：主仓库有 `libunwind`、`libbpf`、`openssl`、`nftables`；packages feed 有 `strongswan 6.0.7`、`libarchive`；无 `numactl`、`libxdp`、`vpp`、`dpdk`。
- Alpine：有 `dpdk`，无 `vpp`。

### 12.2 参考链接

- [vpp-router 仓库](https://github.com/qqdwdbb/vpp-router)
- [vpp-router README](https://github.com/qqdwdbb/vpp-router/blob/main/README.md)
- [vpp-router 安装器](https://github.com/qqdwdbb/vpp-router/blob/main/deploy/install/vpp-router-install.sh)
- [vpp-router Gate 文档](https://github.com/qqdwdbb/vpp-router/blob/main/tools/vpp-egress-gate/README.md)
- [VPP 官方文档](https://docs.fd.io/vpp/26.06/)
- [VPP af_packet 插件源码](https://github.com/FDio/vpp/tree/master/src/plugins/af_packet)
- [DPDK 网卡驱动目录](https://github.com/DPDK/dpdk/tree/main/drivers/net)
- [DPDK AF_XDP PMD 文档](https://doc.dpdk.org/guides/nics/af_xdp.html)
- [ImmortalWrt H5000M 设备树](https://github.com/VIKINGYFY/immortalwrt/blob/owrt/target/linux/mediatek/dts/mt7987a-hiveton-h5000m.dts)
- [ImmortalWrt filogic 镜像定义](https://github.com/VIKINGYFY/immortalwrt/blob/owrt/target/linux/mediatek/image/filogic.mk)
- [Hiveton H5000M 产品页](http://www.hiveton.com/products/detail/h5000m)
- [OpenWrt 主仓库 libunwind](https://github.com/openwrt/openwrt/tree/master/package/libs/libunwind)
- [OpenWrt packages strongSwan](https://github.com/openwrt/packages/tree/master/net/strongswan)
- [Alpine 包索引](https://pkgs.alpinelinux.org/packages)

### 12.3 术语

| 术语 | 含义 |
|:---|:---|
| AF_PACKET | Linux 原始套接字抓包/发包接口；VPP 用它接管无 DPDK 驱动的网卡 |
| AF_XDP | Linux 高性能用户态收包框架；需要驱动 XDP 支持 |
| DPDK | 数据平面开发套件；用户态轮询网卡驱动 |
| HNAT/PPE | MediaTek 硬件 NAT/包处理引擎 |
| WED | Wireless Ethernet Dispatch，WiFi 硬件转发加速 |
| Gate | vpp-router 的按域名/IP 分流程序 |
| procd | OpenWrt 的进程管理/服务框架 |
| netifd | OpenWrt 的网络配置守护进程 |
| UCI | OpenWrt 统一配置接口 |

---

**报告结论**：H5000M 上“让 VPP 跑起来”是可行的，但“把 vpp-router 原样变成默认固件”不可行。建议先用 P0 验证 AF_PACKET + 1GB 内存 + musl 构建这三件事；若通过，再按方案 B 做可选 VPP 包；若任何一项不通过，转向方案 C（Gate/面板能力移植到 OpenWrt），以最低风险获得 vpp-router 的核心价值。
