# 更新日志

本仓库的所有重要变更都会记录在此文件中。

## [2026-10-25] 一次构建固定产出两套固件（MT5700 + MT5700M）

### 背景

两套模组插件独占同一 AT 串口，不能塞进同一份 `.config`，但也不该在触发时让人做选择。
故改为**固定并行**：每次构建都同时编两套固件，各自只含一套插件，分别发布为两个 Release。

### 变更

- `.github/workflows/MTK-AUTO.yml`：`config` 作业改为固定矩阵
  `MODEM: [MT5700, MT5700M]`，每日定时（`Auto-Clean` 完成后）与手动触发都是两个并行作业；
  删除了原来的 `MODEM` 下拉输入。`fail-fast: false`：一套失败不影响另一套继续编译发布。
- `.github/workflows/WRT-BUILD.yml`：同样改为固定矩阵并移除 `MODEM` 下拉输入，
  手动编译一次即产出两套固件。
- `.github/workflows/WRT-CORE.yml`：产物与 Release 增加插件标识，避免两套同名互相覆盖。
  - Release Tag：`<CONFIG>-<SOURCE>-<BRANCH>-<MODEM>-<时间>`
  - 固件文件名：`<原名>-<SOURCE>-<BRANCH>-wifi-yes-<MODEM>-<时间>.<ext>`
  - `.config` 归档名：`Config-<CONFIG>-<SOURCE>-<BRANCH>-<MODEM>-<时间>.txt`
  - Release Notes 增加「模组插件」行，注明两套固件并存、按需下载其中一套。
  - 作业显示名加插件标识，便于在 Actions 列表里区分两个并行构建。
- `README.md`：更新工作流一览、模组插件说明（每次构建产出两套、命名规则）。
- `index.html`：「自动构建中」提示与预期制品清单补充两套固件说明。

### 不兼容说明

- 两套固件**分别**只含一套插件，互不通用；不要在一个固件上手工加装另一套。
- 每次构建占用两个 Runner 并行编译（时长与资源约为原来的两倍）。

### 验证

- 三个 workflow 文件通过 YAML 解析，`bash -n` 通过。
- 矩阵展开核对：`MTK-AUTO` / `WRT-BUILD` 均为 `MT5700` + `MT5700M` 两个作业，
  分别对应 `Config/MT5700.txt` / `Config/MT5700M.txt`。

## [2026-10-25] 新增并深度适配 LianXia233/luci-app-mt5700（旧插件保留，两者互斥不可共存）

### 背景

新增模组管理插件 [LianXia233/luci-app-mt5700](https://github.com/LianXia233/luci-app-mt5700)
（当前 v1.30.4，后端 `at-webserver` 1.29.0）：单包融合 LuCI 前端（12 个页面）与
Rust/Tokio 常驻后端 `/usr/bin/at-webserver-rust`，rpcd ucode 插件经
`nc 127.0.0.1 <port>` 调后端 JSON-RPC，服务 `/etc/init.d/at-webserver`、
配置 `/etc/config/at-webserver`，入口 `网络 → 移动网络 → 5G 模组管理`。

旧插件 `FAN789/luci-app-mt5700m` **保留**（其原生 C 传输程序、流量历史与链路自愈仍有
使用场景），两套插件各自保留完整编译配置，但同一份 `.config` 只能启用其中一套。
直接接入会踩三个坑，故本次做深度适配：

1. **Rust 后端无法在 buildroot 内编译**：`rules.mk` 在包编译阶段
   `export PATH:=$(TARGET_PATH)`，PATH 里没有 `~/.cargo/bin`；改用
   `feeds/packages/lang/rust` 的 host rust 需现场编译 LLVM（1~2 小时、约 20GB 磁盘）。
2. **两套插件争抢 AT 串口**：旧插件由 `mt5700m-transport` 持有串口，新插件由
   Rust 后端持有，同时启用必然随机超时，必须在配置层强制互斥。
3. **风扇温控失去模组温度**：`luci-app-h5000m-fancontrol` 读
   `/var/run/mt5700m/temperature`（`updated=` 秒级时间戳 + `temperature=`，60 秒老化），
   该文件由旧插件的 `mt5700m-manager` 维护；新插件把温度留在自己的后端缓存里。

### 变更

- `Config/`：
  - 新增 `Config/MT5700.txt`（新插件：`luci-app-mt5700` + `luci-i18n-mt5700-zh-cn`）
    与 `Config/MT5700M.txt`（旧插件：`luci-app-mt5700m` +
    `luci-i18n-mt5700m-zh-cn` + `flock`），两套编译配置并存。
  - `Config/GENERAL.txt` 不再写死模组插件包，只保留两套插件共用的 `odhcp6c`
    （蜂窝 IPv6 租约），并注明 `nc` / `timeout` 来自 busybox 默认配置
    （`BUSYBOX_DEFAULT_NC` / `TIMEOUT` 默认 y）、`luci-base` 已带 `rpcd` +
    `rpcd-mod-ucode` + ucode 模块，无需额外选包。
- `Scripts/Packages.sh`：
  - 两套插件**都 clone**：恢复 `UPDATE_PACKAGE "luci-app-mt5700m"
    "FAN789/luci-app-mt5700m" "main"`，新增 `UPDATE_PACKAGE "luci-app-mt5700"
    "LianXia233/luci-app-mt5700" "main"`；删除 `qmodem`（FUjr/QModem）clone 行
    ——该行此前与注释不一致，实际仍在 clone，且 QModem 同样争抢串口。
  - 分别做克隆结构校验：新插件 11 个必需文件（`src/Makefile`、
    `src/rust/{Cargo.toml,Cargo.lock}`、init.d、config、ucode、menu.d/acl.d、
    一个 htdocs 视图、po）；旧插件 6 个必需文件（两个 Makefile、
    `transport.c`、`mt5700m-manager`、init.d、po）。
  - 版本分别写入 `GITHUB_ENV` 的 `MT5700_VERSION`（插件 / 后端）与
    `MT5700M_VERSION`（插件 / transport）。
  - `PREPARE_MT5700_PREBUILT()`：幂等改写 `src/Makefile` 的 `compile` 目标——
    存在 `src/prebuilt/at-webserver` 时直接复制到 `$(BIN)`，否则回退上游
    `cargo build`；带 `MT5700_PREBUILT_HOOK` 标记，`re.subn` 命中数不为 1 或
    缺少 `install:` 目标时立即失败（上游改结构会显式报错而不是静默编旧逻辑）。
  - `INJECT_MT5700_TEMP_BRIDGE()`：注入 `root/usr/sbin/mt5700-temp-bridge`
    （每 30s 经 `ubus call mt5700 at` 取 `AT^CHIPTEMP?`，解析 12 路传感器、
    取峰值，按旧格式原子写入 `/var/run/mt5700m/temperature`）、
    `root/etc/init.d/mt5700-temp-bridge`（procd，START=99）与
    `root/etc/uci-defaults/93-mt5700-temp-bridge`（首次启动 enable）。
    这些文件只随新插件打包，选旧插件时不会进固件。
- `.github/workflows/WRT-CORE.yml`：
  - 新增 `workflow_call` 输入 `WRT_MODEM`（`MT5700` / `MT5700M`，未传时默认
    `MT5700`）。
  - `Custom Settings` 只追加 `Config/${WRT_MODEM}.txt` 这一份插件配置；
    `make defconfig` 后做**互斥校验**——两套主包同时为 `y`、与所选
    `WRT_MODEM` 不一致、或缺配套语言包，全部立即 `exit 1`（无论问题来自配置文件
    还是 `WRT_PACKAGE` 手工追加）。
  - 原有 smoke test 改名 `Smoke Test luci-app-mt5700` 并加
    `if: env.WRT_MODEM != 'MT5700M'`；同时恢复旧插件的
    `Smoke Test luci-app-mt5700m`（原先的 shell 语法 / 回归、`transport.c`
    `-Werror` 编译与模拟测试、可执行位、JS 语法、UI/短信、JSON、msgfmt 全套），
    以 `if: env.WRT_MODEM == 'MT5700M'` 触发。
  - 新增 `Cross Compile Rust Backend` 步骤（`Custom Settings` 之后、
    `Download Packages` 之前，仅在选新插件且非 TEST 时执行）：从 `.config` 读
    `CONFIG_TARGET_ARCH_PACKAGES`，非 `aarch64_cortex-a53` 直接失败（目标架构
    不符会「装得上、跑不起来」）；rustup 安装 `aarch64-unknown-linux-musl`
    target，pip 安装 `ziglang==0.13.0` 作交叉链接器（含 cc-rs 兼容包装：丢弃
    外部 `--target=`、过滤 `--fix-cortex-a53-843419`），
    `cargo build --release --locked` 后校验「ARM aarch64 / statically linked /
    无动态段 / 体积 > 1MB」，再拷到 `package/luci-app-mt5700/src/prebuilt/at-webserver`。
  - 新插件的翻译校验用 **`po2lmo` 编译**而非 `msgfmt --check`：上游 po 有 2 处
    重复 msgid（`msgfmt --check` 判 fatal），而 luci.mk 实际用 po2lmo 编译 lmo，
    故从 feed 的 `luci-base/src` 现场构建 po2lmo，口径与打包一致。
  - Release Notes 版本行改取 `MT5700_PLUGIN_VERSION`（按 `WRT_MODEM` 取对应版本串）。
- `.github/workflows/WRT-BUILD.yml` / `MTK-AUTO.yml`：透传 `WRT_MODEM`（当时为
  下拉选择，随后改为固定矩阵 —— 一次触发并行产出两套固件，见上一条）。
- `README.md` / `index.html`：新增模组插件说明（两套配置、互斥规则、两套固件各含一套），
  插件章节更新为 `luci-app-mt5700`（12 页面矩阵、服务与配置路径、
  温度桥接、预编译后端构建方式），并补充旧插件作为另一套固件的模组管理方案。

### 不兼容说明

`luci-app-mt5700`、`luci-app-mt5700m`、QModem 都独占 MT5700M 的 AT 串口，
三者两两不能共存。本仓库每次构建并行产出两套固件、每套只启用一套插件：
两套配置（`Config/MT5700.txt` / `Config/MT5700M.txt`）都保留，但同一份 `.config`
不允许同时启用，CI 会强制拦截。下载时按需选其中一套；装好固件后
也不要再从软件源手工加装另一套。

### 验证

- 本地用同一套 rustup + zig 交叉编译流程构建后端：
  `cargo build --release --locked --target aarch64-unknown-linux-musl` 用时
  2 分 01 秒，产物 2724136 字节、`ELF 64-bit LSB executable, ARM aarch64,
  statically linked, stripped`、无动态段（`ring` 的 C 代码经 zig cc 编译通过）。
- 上游 10 个 node 回归测试全部通过；htdocs JS `node --check` 全部通过；
  menu.d / acl.d `jq empty` 通过；9 个 shell 脚本 `sh -n` 通过；
  `po2lmo` 编译 `po/zh_Hans/luci-app-mt5700.po` 成功产出 lmo。
- 互斥校验用三种 `.config` 实测：仅新插件（1/0）、仅旧插件（0/1）通过，
  两者同时为 y（1/1）被拦截。
- 三个 workflow 均通过 YAML 解析与 `bash -n`；`Scripts/Packages.sh` 通过 `bash -n`。
- 待实机验证：`/etc/init.d/at-webserver` 拉起后端、`admin/modem/5g` 菜单渲染、
  风扇插件读到 `mt5700-temp-bridge` 写入的温度、`MT5700M` 接口自动创建；
  以及选 `MT5700M` 时旧插件路径的构建产物。

### 备注

上游 `src/rust/Cargo.toml` 的 `version = "1.29.0"` 与顶层 `Makefile` 的
`PKG_VERSION:=1.30.4` 不一致（上游自身问题），本仓库不改上游文件，
仅在 `MT5700_VERSION` 中同时记录两者。

## [2026-10-25] 修复机型回退导致编译失败 + 清理 Node 20 弃用告警

### 背景

10-24 凌晨的 MTK-AUTO（run 40140034404，MEDIATEK-WIFI-YES / VIKINGYFY/immortalwrt）
在「Compile Firmware」失败，耗时 3 小时 37 分。日志显示构建的是
**OpenWrt One** 而非目标机型 Hiveton H5000M，`hiveton` 关键字在整份日志中出现 0 次。

### 根因

1. **机型静默回退（编译失败主因）**
   OpenWrt/ImmortalWrt 的「Target Profile」是单选 choice，`scripts/target-metadata.pl`
   生成两层不同符号：
   - `MULTI_PROFILE=y`：`Target Devices` 菜单中的
     `CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xxx`；
   - `MULTI_PROFILE=n`：`Target Profile` choice 中的
     `CONFIG_TARGET_mediatek_filogic_DEVICE_xxx`（无 `DEVICE_` 前缀那一层）。

   `Config/MEDIATEK-WIFI-YES.txt` 在 `MULTI_PROFILE=n` 下只写了
   `CONFIG_TARGET_DEVICE_...`，该符号此时不可见，`make defconfig` 静默回退到
   `target/linux/mediatek/filogic/target.mk` 的 `DEFAULT_PROFILE`（filogic 平台为
   `openwrt_one`），于是编译了 OpenWrt One。该机型出厂镜像依赖 initramfs，而
   `Config/GENERAL.txt` 中 `CONFIG_TARGET_ROOTFS_INITRAMFS=n`，导致
   `immortalwrt-mediatek-filogic-openwrt_one-initramfs.itb` 未生成、
   `ubinize-image.sh` 打包 factory.ubi 时 `stat: cannot statx` 失败，
   `target/linux failed to build` → `make world` 退出。
   （2026-10-23 将 `MULTI_PROFILE` 改回 `n` 的改动本身没有错，错在设备配置写的是
   另一层符号。）

2. **Node 20 弃用告警**：`actions/checkout@v4`、`actions/cache@v4`、
   `actions/github-script@v7`、`softprops/action-gh-release@v2` 均运行在 Node 20
   runtime 上，runner 会强制切到 Node 24 并给出弃用告警。

### 修复

- `Config/MEDIATEK-WIFI-YES.txt`：改用单选 choice 符号
  `CONFIG_TARGET_mediatek_filogic_DEVICE_hiveton_h5000m=y`，并在注释中说明两种
  符号的区别；同步修正 `Config/GENERAL.txt` 中关于 10-23 那次误判的注释。
- `.github/workflows/WRT-CORE.yml`：`Custom Settings` 在 `make defconfig` 之后新增
  目标设备校验——从 `Config/$WRT_CONFIG.txt` 提取设备符号并检查其已进入 `.config`，
  未生效则立即 `exit 1`。同类配置错误从此在数分钟内失败，而不是数小时后。
- Node 20 清理（均切换到 Node 24 runtime）：
  `actions/checkout@v4` → `v7`，`actions/cache@v4` → `v6`，
  `actions/github-script@v7` → `v9`（脚本仅用 `github.rest`，v9 新增的
  `getOctokit` 注入函数不影响），`softprops/action-gh-release@v2` → `v3`。
- `runs-on: ubuntu-latest` → `ubuntu-24.04`（WRT-CORE / Cache-Clean / Auto-Clean）：
  `ubuntu-latest` 自 2026-10-19 起会迁移到 Ubuntu 26.04，而 immortalwrt 初始化脚本
  与部分 host 依赖尚未适配，固定镜像保证可复现构建。
- `actions/checkout` v7 会拦截 fork PR 的 `workflow_run` 检出；本仓库触发方式为
  `schedule` / `workflow_dispatch` / 同仓库 `workflow_run`，不受影响。

### 验证

- 本地核对 `scripts/target-metadata.pl` 生成的 Kconfig 结构，确认
  `MULTI_PROFILE=n` 时生效符号不含 `TARGET_DEVICE_` 前缀。
- 本地核对 `target/linux/mediatek/image/filogic.mk`，确认
  `Device/hiveton_h5000m` 仅产出 `sysupgrade.bin`（无需 initramfs）。
- 触发 MTK-AUTO（TEST=true）验证 `Custom Settings` 校验逻辑与配置文件正确性。

## [2026-10-23] 深度适配 FAN789/luci-app-mt5700m v3.0.3

### 背景

luci-app-mt5700m 已迭代至 3.0.3：以自有原生 C 程序 `mt5700m-transport`
替代 `ubus-at-daemon` / `sms-tool` / QModem 服务，运行时依赖收敛为
`luci-base`、`mt5700m-transport`、`flock`、`curl`、`odhcp6c` 与六个 USB
kmod。本仓库虽已基础集成，但存在配置覆盖冲突、依赖缺失、文档过时
与无回归防线四项问题，本次一并修复。

### 变更

- `Config/GENERAL.txt`：`CONFIG_TARGET_MULTI_PROFILE` 由 `y` 改回 `n`。
  该配置后于设备配置（`MEDIATEK-WIFI-YES.txt` 中为 `n`）追加进 `.config`，
  Kconfig 对重复符号后读覆盖，实际一直编译整个 filogic 平台全部 profile
  （数十台设备），与「仅编译 Hiveton H5000M」意图相反；同步将
  `CONFIG_TARGET_PER_DEVICE_ROOTFS` 改为 `n`（单设备构建下无意义）。
- `Config/GENERAL.txt`：补充 MT5700M 运行时依赖 `flock` 与 `odhcp6c`
  （上游 README 点名组件；USB kmod 六件套此前已齐备）。
- `Scripts/Packages.sh`：移除 `qmodem`（FUjr/QModem）clone。该插件从未
  被本固件启用，且与 luci-app-mt5700m 争抢同一 AT 串口；luci-app-mt5700m
  3.0.x 已完整覆盖其功能。恢复方法见脚本内注释。
- `Scripts/Packages.sh`：新增 FAN789 仓库结构校验与版本记录——校验
  `luci-app-mt5700m/` 与 `mt5700m-transport/` 两个 Makefile 存在
  （immortalwrt `include/scan.mk` 以 `SCAN_DEPTH=5` 扫描 package/ 树，
  二级子目录可被正常识别），并将版本号写入 `GITHUB_ENV`（`MT5700M_VERSION`）。
- `.github/workflows/WRT-CORE.yml`：
  - 新增 `Free Up Disk Space` 步骤，清理 runner 预装的 dotnet /
    android-sdk / ghc 等无关目录（约 25GB），保障 filogic 全量编译
    与 ccache 空间。
  - 新增 `Smoke Test MT5700M Package` 步骤：在耗时编译前，对 clone 的
    luci-app-mt5700m 执行上游 `ci.yml` 同款检查——shell 语法与回归测试、
    `mt5700m-transport` C 程序编译（`-Wall -Wextra -Werror`）与模拟 modem
    测试、可执行位、LuCI JS 语法、UI 错误处理、短信解码 / 任务、健康
    恢复、配置回滚、menu/acl JSON 与 zh_Hans 翻译文件校验。上游引入
    破坏性变更时在数分钟内失败，而非数小时后在 Compile Firmware 暴露。
  - `Initialization Environment` 安装 `gettext`（提供 `msgfmt`）。
  - Release Notes 新增「MT5700M 插件版本」行。
- `README.md`：MT5700M 插件章节按 3.0.x 实际架构重写（自有
  `mt5700m-transport`、短信 UTF-16 多段、流量历史、温度缓存、链路健康
  自愈、APN 回滚），删除 `ubus-at-daemon` / `sms-tool` 过时描述；
  修正 Auto-Clean 行为描述（清理全部历史 Release，与实际配置一致）。
- `.gitattributes`：由仅覆盖 `*.txt` / `*.sh` 升级为 `* text=auto eol=lf`，
  覆盖 `.yml` / `.json` 等全部文本文件，保证任何平台提交均为 LF。
- `index.html`：MT5700M 亮点卡片补充 3.0.x 特性描述。

### 验证

- 本地对全部 workflow 执行 YAML 解析校验，对全部脚本执行
  `bash -n` / `sh -n` 校验。
- 本地模拟 Kconfig 后读覆盖行为，确认 MULTI_PROFILE 修复后
  `.config` 终态为 `n`。
- Smoke Test 全部命令在本地对 clone 的 FAN789/luci-app-mt5700m
  （93f6a65）干跑通过。完整编译链路由下一次 MTK-AUTO 定时构建覆盖。

## [2026-10-23] 修复初始化环境超时导致 CI 失败

### 背景

10-23 凌晨的 MTK-AUTO（run 39874026966，MEDIATEK-WIFI-YES / VIKINGYFY/immortalwrt）
在「Initialization Environment」步骤失败，而前两日同一 commit（e94bf52）构建均正常。

### 根因

runner 镜像 20261012 更新后，`apt full-upgrade` 待升级包增至 98 个，并新增
linux-azure 7.0 内核等 10 个包。下载与解包耗时超过 `apt_retry` 中统一的
`timeout 300`：日志显示三次尝试分别在 23:47:18 / 23:52:17 / 23:57:27 开始，
均于整 300 秒被杀，重试耗尽后步骤以 exit 1 结束。
此前同一构建该步骤耗时 5:12 / 5:46，本就接近 300 秒上限，属镜像更新后被推过阈值。

### 修复

- `.github/workflows/WRT-CORE.yml`：`apt_retry` 改为按命令传入超时
  （update 300s、install 900s、full-upgrade 1800s），避免慢速下载被误杀。
- 主机系统升级并非编译必需：`full-upgrade` 失败后执行
  `dpkg --configure -a` / `apt -f install` 修复状态并继续，不再中断 job。
- `init_build_environment.sh` 超时 600s → 1800s；三次均失败时显式 `exit 1`
  （原实现会静默跳过失败继续执行）。
- `timeout` 增加 `--kill-after=30` 防止残留进程，apt/dpkg 增加
  `--force-confdef` / `--force-confold` 非交互选项；`Acquire::Retries` 3 → 5。

### 验证

手动 workflow_dispatch 触发 MTK-AUTO（TEST=true，跳过编译）run 39888490893
全流程成功，`Initialization Environment` 耗时 4 分 42 秒、`full-upgrade`
一次通过。完整编译链路由次日定时构建覆盖验证。

## [2026-10-18] 切换构建源码：immortalwrt/immortalwrt@master → VIKINGYFY/immortalwrt@owrt

### 背景

此前全量定时（MTK-AUTO）与手动（WRT-BUILD）构建均基于官方
`immortalwrt/immortalwrt@master`。为与 VIKINGYFY 生态（构建脚手架与
`VIKINGYFY/packages` feed）保持同源、降低跨仓库版本漂移，现将底层源码
切换为 `VIKINGYFY/immortalwrt` 的 `owrt` 分支（commit 99c39ee）。

### 变更

- `MTK-AUTO.yml`：定时/自动构建 matrix 由 `SOURCE: [immortalwrt/immortalwrt]` /
  `BRANCH: [master]` 改为 `SOURCE: [VIKINGYFY/immortalwrt]` / `BRANCH: [owrt]`。
- `WRT-BUILD.yml`：手动触发默认 `SOURCE` 改为 `VIKINGYFY/immortalwrt`，默认
  `BRANCH` 改为 `owrt`，并同步更新分支选择说明（VIKINGYFY 用 owrt，immortalwrt 用 master）；
  官方 `immortalwrt/immortalwrt` 仍保留为可选源码，便于随时回退。
- `index.html`：落地页“固件源码”徽章与规格卡同步更新为 VIKINGYFY/immortalwrt@owrt。
- `README.md`：标题、ImmortalWrt 徽章、底层底包与维护周期中的构建源码表述同步更新为 VIKINGYFY/immortalwrt@owrt。
- 打包产物命名随之变化：`WRT_INFO`=VIKINGYFY、Release Tag 携带 `-owrt-` 后缀，
  与既有“按变体清晰区分”策略一致。
- packages feed 仍为 `VIKINGYFY/packages@main`（独立仓库，本次未改动），与源码同源。

### 影响

- 内核版本、插件清单、Release 标签将反映 VIKINGYFY/immortalwrt@owrt 的真实提交。
- 首次基于 owrt 分支构建将因源码变化而命中新的缓存键（ccache/toolchain），
  首次编译耗时可能增加，属预期行为。

## [2026-10-17] 修复全平台编译中断：移除 immortalwrt/packages 中过时的 miniupnpd 补丁

### 背景

10-17 凌晨的 MTK-AUTO（run 38979810271，MEDIATEK-WIFI-YES 变体）在
「Compile Firmware」步骤失败，前一日（10-16 合并前）构建正常。

### 根因

immortalwrt/packages 于 2026-10-16 03:02 UTC 执行「Merge Official Source」（dd29469e22），
将 openwrt/packages 上游 10-07 的 miniupnpd 2.3.11 升级合入。feed 自带的
`net/miniupnpd/patches/020-descr-filter-fix.patch`（权限行解析器重写）基于 2.3.9
编写，2.3.11 的 `upnppermissions.c/h` 已发生变动，导致 7 个 hunk 中 5 个
apply 失败、prepare 阶段即中断，miniupnpd(nftables) 编译失败并级联到
`make world` 退出。

经比对 miniupnpd 2.3.11 官方源码确认：该补丁的全部改动（`get_sep`/`get_ushort`/
`get_range`/`iseol` 解析器重写、`read_permission_line` 的 `const char *` 签名）
均已被上游吸收，补丁完全过时，删除无功能损失。与 H5000M-CI-Qmodem 同日
修复（commit 4e881f7）为同一问题。

### 修复

- `.github/workflows/WRT-CORE.yml`：Update Feeds 步骤后增加 workaround，
  若存在 `feeds/packages/net/miniupnpd/patches/020-descr-filter-fix.patch`
  则删除之。MTK-AUTO / WRT-BUILD 均复用 WRT-CORE，一处修复全覆盖。
  上游刷新补丁后可移除该 workaround。

### 验证

推送后手动 workflow_dispatch 触发 MTK-AUTO，观察 Compile Firmware 步骤
通过、固件产物生成。

## [2026-10-10]

### 变更

- **移除 MT5700M 依赖冗余组件**：应 issue #2 反馈，从固件配置中移除 `ubus-at-daemon`（默认串口与 MT5700M 不匹配、未被网页调用，纯占内存）与 `sms-tool` / `sms-tool_q`（短信工具，避免与上游拨号插件自带工具冲突）。后续构建的固件不再包含这三个包；`mt5700m-manager` 层面的功能改进（USB 3.0 自愈等）请反馈至上游 FAN789/luci-app-mt5700m。

### 变更文件

- `Config/GENERAL.txt` — 删除 `ubus-at-daemon`、`sms-tool`、`sms-tool_q` 三个配置项（commits 2a0c20e / 2f99243）

## [2026-09-25]

### 修复

- **sing-box 过时补丁导致构建失败**：今日（09-24）定时构建 `failure`，首个失败步骤为「编译固件」。根因为 `Scripts/Packages.sh` 克隆的 viking feed（`VIKINGYFY/packages`）中 sing-box 自带 `patches/100-fix-dns-tcp-close.patch` 与 `1.15.0_alpha8` 源码上下文不匹配（补丁引入的上游从未合入的 `HandleStreamDNSConnection`，而源码仍是 `HandleStreamDNSRequest`），`Build/Prepare` 阶段应用补丁报 `Patch failed!` 并 `Error 1`，整个固件编译中断。上游 `immortalwrt/packages` 的 sing-box 根本不携带该补丁也能正常构建，故判定为可安全移除的过时补丁。已在克隆 viking feed 后新增 `FIX_SINGBOX_STALE_PATCH`：仅当补丁内容含旧版标记 `HandleStreamDNSConnection` 时移除，若 VIKINGYFY 后续刷新补丁则自动跳过、不误删。

### 变更文件

- `Scripts/Packages.sh` — 新增 `FIX_SINGBOX_STALE_PATCH`（克隆 viking feed 后清理过时 sing-box 补丁）

## [2026-08-25]

### 新增

- **TTYD Web 终端**：全机型默认集成 [ttyd](https://github.com/tsl0922/ttyd) 网页命令行终端，LuCI「系统 → TTYD 终端」页面可在浏览器直接操作设备 Shell。`Config/GENERAL.txt` 新增并默认启用 `ttyd`、`luci-app-ttyd`、`luci-i18n-ttyd-zh-cn` 三个软件包。

### 变更文件

- `Config/GENERAL.txt` — 新增 TTYD Web 终端配置段（`ttyd` / `luci-app-ttyd` / `luci-i18n-ttyd-zh-cn`，均默认启用）
