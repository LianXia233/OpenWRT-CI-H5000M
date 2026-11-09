# 更新日志

本仓库的所有重要变更都会记录在此文件中。

## [2026-11-09] 修复冷编译超时（run 130 失败）

### 背景

`MTK-AUTO` 运行 130（2026-11-09 00:20 UTC）两个作业均在 `Compile Firmware` 失败，退出码 124。
日志显示这不是代码错误：`timeout` 在 90 分钟处 SIGTERM 了 `make`，降级的 `make -j1 V=s`
又在 120 分钟处被 SIGTERM，最后一次时 MT5700 停在 `hostpkg/Python-3.14.7`、MT5700M
停在 `toolchain/gcc/final`，两者合计恰好 3.5 小时 = 5400 + 7200 秒。

trigger 是周日的 `Cache-Clean`（cron `0 20 * * 0`，本次 23:23 UTC 执行）删除了全部 Actions
缓存：`Check Caches` 实测 `caches missed!`，仓库缓存列表为空，于是两个作业同时进入冷编译。
冷编译在 4 核 runner 上要编 `tools/llvm-bpf`（clang）、两遍 gcc、全量 package 与镜像，
实测 3.5 小时仍未完成；而失败作业不会保存新缓存，下一次运行依旧是冷编译，形成循环。

### 变更

- `WRT-CORE.yml` 的 job 上限 `timeout-minutes: 300` → `360`（GitHub 上限），让每周一次的
  冷编译有足够时间窗跑完，进而把缓存写回去。
- `Compile Firmware` 由「5400s 并行 + 7200s 降级 -j1」改为「300 分钟总预算 + 45 分钟等长
  分片续编」，全程保持 `-j$(nproc)`：
  - 超时只中断当前分片，`make` 幂等，下一分片从断点继续，损失仅为被 SIGTERM 打断的个别
    编译单元；不再把 4 核降为单线程（旧降级正是第二轮毫无进展的原因）。
  - 源码包按需下载挂起同样被单个分片收束，下一分片重新轮换镜像，不会一次挂起吃掉整轮预算。
  - 退出码 124/137 视为超时继续续编；连续 2 次非超时失败判为真实编译错误立即终止，
    避免在剩余预算里空转。
  - 编译返回 0 后额外核对 `bin/targets` 下确有固件镜像（`.bin`/`.img`/`.itb`/`.squashfs`）。

### 验证

- `WRT-CORE.yml` 经 `yaml.safe_load` 解析通过（26 步），22 个 `run` 块逐块 `bash -n` 通过。
- 用 mock `make` 跑通编译分片循环的三个分支：首次超时→续编成功（exit 0）；真实编译错误→
  两次后立即 exit 1（不空转）；持续超时→预算耗尽 exit 1 并打印卡点。
- 文件为 UTF-8（无 BOM）、纯 LF。
- 未验证：完整冷编译需在下一次 Actions 运行中观察（预计 4 小时量级）。

## [2026-11-08] 接入 luci-app-online-upgrade（全机型）并按机型预设升级源

### 背景

需求是把同作者的 `LianXia233/luci-app-online-upgrade` 接入本仓库**所有机型**，并让每套固件
开箱即指向「自己那一组」发布产物。本仓库的机型维度是模组方案（`MT5700` / `MT5700M`），
设备唯一（Hiveton H5000M，`mediatek/filogic`），构建矩阵固定并行产出两套固件，因此
升级源必须按 `WRT_MODEM` 隔离，且不能写死一份静态配置共用。

插件是「Rust 后端 + ucode rpcd + LuCI 前端」的 v2 实现，上游 `Build/Prepare` 与
`Build/Compile` 均为空——按 OpenWrt 常规流程编译会得到一个没有 `/usr/bin/online-upgrade`
的空壳包，因此接入必须同时解决**包导入**与**二进制预编译落位**两件事。

### 变更

- 新增 `Scripts/Packages-OnlineUpgrade.sh`：clone 上游到 `package/luci-app-online-upgrade`
  （直连失败回退 `https://gh.acg2.mom/` 镜像），清 `.git` / `.github`，文本文件 CRLF→LF
  并按字节复核；结构断言覆盖 `feeds/luci/luci.mk`、`./root/usr/bin/online-upgrade` 安装项、
  `$(1)/usr/bin/online-upgrade` 安装目标、`rust/Cargo.{toml,lock}`、默认 UCI 配置与
  `[profile.release]` 收敛项（`opt-level="z"` / `lto` / `codegen-units=1` / `panic="abort"` /
  `strip`）；建 `root/usr/bin` 供预编译产物落位。
- `90-online-upgrade-auto` 的守卫处理改为**按内容判定、幂等**：上游已在 `98a966a`
  （2026-11-08）把守卫改成 `[ -x /usr/bin/online-upgrade ] && exit 0` /
  `if [ ! -x /usr/bin/online-upgrade ]`，不再引用 v1 的 `online-upgrade.sh`。本仓库仅在
  检测到 v1 路径时才改写，上游已修复则跳过；无论是否改写都断言最终代码行引用 v2 路径且
  不含 v1 引用，同时核对 Makefile 安装项与守卫路径一致。
- `Scripts/Settings.sh`：追加 `CONFIG_PACKAGE_luci-app-online-upgrade=y`，并在 `.config`
  已包含该符号后调用预设脚本。
- 新增 `Scripts/OnlineUpgradePreset.sh`：从 `Config/$WRT_CONFIG.txt` 解析设备符号
  （平台 + 设备），结合 `WRT_MODEM / WRT_INFO / WRT_BRANCH` 生成
  `files/etc/config/online-upgrade`。键名以 `rust/src/uci.rs`（section `online-upgrade.settings`）、
  `github.rs`、`downloader.rs`、`upgrade.rs` 为准；上游默认配置里的 `enabled`、`keep_config`
  代码并未读取，故不写入。
- `WRT-CORE` 新增三个步骤：
  - `Import Online Upgrade Package`（`Custom Packages` 之后，两套固件都执行）；
  - `Rust Cache Key` + `Rust Build Cache`（`actions/cache@v6`，缓存 `~/.cargo/registry`、
    `~/.cargo/git` 与后端 `target`，键含 `Cargo.lock` 的 sha256）；
  - `Prepare Rust Toolchain`（原 `Cross Compile Rust Backends` 里的 rustup 与 zig 包装抽出来
    供两套固件共用，因此 `MT5700M` 作业也能编译在线升级后端）；
  - `Cross Compile Online Upgrade Backend`（`--locked --release` 交叉编译后落到
    `package/luci-app-online-upgrade/root/usr/bin/online-upgrade`，含 aarch64 / 静态链接 /
    无动态段 / 体积四项自检）。
- `Custom Settings` 在 `make defconfig` 后硬性校验
  `luci-app-online-upgrade`、`rpcd-mod-ucode`、`ucode-mod-fs`、`ucode-mod-uci` 均为 `y`，
  避免「主包启用但运行期依赖缺失」留到刷机后暴露。
- Rust 编译方式统一为**官方工具链**（rustup stable + `aarch64-unknown-linux-musl`）：
  不使用 `feeds/packages/lang/rust`（需现场编译 host LLVM，1~2 小时、约 20GB，且产物
  链接目标板 musl 动态库、panic/strip 策略与本仓库既有静态 musl 二进制不一致）；
  链接器沿用 zig cc（与上游 `scripts/sdk-build.sh` 同方案，提供 musl libc 与启动对象）；
  新增 `-C target-cpu=cortex-a53`（对齐 `ARCH_PACKAGES=aarch64_cortex-a53`），
  不使用 `target-cpu=native`（runner 为 x86_64，会编出跨架构不可用的产物）。

### 验证

- `bash -n`：`Packages-OnlineUpgrade.sh`、`OnlineUpgradePreset.sh`、`Settings.sh` 全部通过。
- YAML：`WRT-CORE.yml` 经 `yaml.safe_load` 解析通过。
- 预设按机型模拟生成：`MT5700` / `MT5700M` 各生成一份配置，正则对**真实 Release 资产名**
  匹配（`mediatek-filogic-hiveton_h5000m-squashfs-sysupgrade-VIKINGYFY-owrt-wifi-yes-*.bin`），
  并验证两个模组的正则互相不误匹配、`tag` 正则不跨组。
- 导入脚本实跑：clone 上游 `98a966a` 后结构断言与守卫断言全部通过，CR 计数为 0。
- LF / UTF-8：新增与修改文件均为纯 LF，无 BOM。
- 脱敏扫描：本次差异不含任何密钥、令牌或个人信息。
- Rust 后端编译耗时（本机 Windows 上 `cargo build --release --locked --target
  aarch64-unknown-linux-musl`，zig 提供 musl 链接；runner 侧数据需 CI 复测）：
  - 清空 target 的冷构建：**108.0 秒**，产物 3,049,760 字节（AArch64、静态链接、
    无 `.dynamic` / `.interp`）；
  - target 命中且源码无改动：**0.4 秒**；
  - 仅改业务代码（重编 crate + LTO 重链接）：**34.8 秒**。
  本机 cargo registry 已是热态，故冷构建不含 crates 下载；CI 上缓存另可省去
  registry 拉取。作为参照，改造前 CI 的 `Cross Compile Rust Backends` 步骤
  （风扇控制器 + at-webserver 两个后端）实测 87 秒。

### 未验证

- 完整固件编译未在本机执行（需完整 OpenWrt 工具链与数小时构建）。新增步骤的
  端到端结果（`make defconfig` 是否拉齐三件 ucode 依赖、交叉编译产物在设备上运行、
  LuCI 升级页面取到正确 Release）留待 CI 验证。

## [2026-11-07] 修复上游源码包与 Rust 工具链下载挂起导致的 runner 失联

### 背景

11-06 的 apt 镜像修复（`Select Apt Mirror` 测速切换 + 孤儿死锁治理）当天验证通过，
11-07 00:30 UTC 随 `Auto-Clean` 触发的 `MTK-AUTO`（run 128）却以更隐蔽的方式失败：
两个 job 先后 `The hosted runner lost communication with the server`，且日志端点
404（BlobNotFound），一个字节的日志都没能留下。逐步骤时间戳对比前一日成功运行
（run 127）后才定位：

| Job | 死点 | 本次实测 | 前日成功基准 |
| --- | --- | --- | --- |
| MT5700M | `Download Packages`（`make download`） | 卡 77 分钟后失联 | 82 秒 |
| MT5700 | `Cross Compile Rust Backends` | 卡约 100 分钟后失联 | 87 秒 |

前置步骤（apt 测速、init、feeds、Smoke Test）全部正常且耗时与前日一致 ——
说明 apt 侧修复有效，这次是**同类事故换了个地方发生**：源码包镜像与 Rust 工具链
下载链路（crates.io 索引 / rustup dist / PyPI）「连上但吞吐趋零」。与 11-06 的
apt 镜像事故共享同一结构性缺陷：

- `download.pl` 的多镜像轮换只在**连接失败**时触发，慢速挂起永远不会切换；
- `cargo` / `rustup` / `pip` 对下载均无默认总超时；
- job 级 `timeout-minutes: 300` 的兜底在 ~1.5 小时 runner 被环境回收面前
  永远等不到触发，于是既丢日志、也丢诊断线索，只能靠猜。

### 变更

- **`Download Packages` 收束 + 降级重试**：首轮 `timeout --kill-after=60 900
  make download -j$(nproc)`（基准 82~112 秒，上限 15 分钟）；超时或失败后降级
  `-j1 V=s` 逐文件重试（上限 30 分钟）—— 单线程下 `download.pl` 为每个文件
  轮换下一个镜像源，是社区通行的自愈路径。源码包先落 `tmp/dl`、校验哈希通过
  才进 `dl/`，中断不留损坏文件，重试只补缺失部分。`timeout` 直接包 `make`
  （无 `sudo` 夹层），其自建进程组能让 SIGTERM/SIGKILL 命中全部下载子进程，
  不会重演 11-06 的孤儿锁事故。
- **`Cross Compile Rust Backends` 四个下载点逐一收束**：
  - rustup-init 改为先落盘再执行（`--connect-timeout 30 --max-time 120`），
    与 init 脚本同款套路 —— `curl | sh` 模式下 curl 挂死会让 sh 读到空内容
    并以 0 退出，缺工具链要到几小时后的编译阶段才暴露；
  - `rustup target add`（约 200MB 标准库）套 `timeout 900`，失败重试一次；
  - `cargo test`（零依赖 crate）套 `timeout 900`；
  - 两处 `cargo build` 套 `timeout`（风扇控制器 1200 / at-webserver 1800，
    后者含 Tokio + rustls + ring 依赖树下载与 zig 链接），失败重试一次，
    中断只影响未完成编译单元，重跑从 target 缓存续建；
  - `pip install ziglang` 加 `--timeout 60 --retries 3`。
- **`Compile Firmware` 首轮同样收束**：编译期偶有按需补下载源码包，属同一风险。
  首轮 `-j$(nproc)` 套 `timeout 5400`（基准 ~35 分钟），失败仍降级 `-j1 V=s`
  断点续编（套 `timeout 7200`）。两层上限合计 210 分钟，仍小于 job 级
  `timeout-minutes: 300`，保证兜底链完整。

未改编译参数、缓存键与任何构建逻辑；所有收束上限均为对应基准耗时的 8 倍以上，
正常构建不受影响。

## [2026-11-06] 修复有界重试自身的孤儿 apt 死锁，并把镜像测速换成真实批量负载

### 背景

上一笔「上游 apt 镜像吞吐退化时自动切换」（PR #3，`96defd4`）合入后，当天
12:26 UTC 的 `MTK-AUTO`（run 124）仍失败，且两个 job 各自暴露了新问题：

**1. `Select Apt Mirror` 的测速目标选错了，而且方向是反的。** run 124 日志里它打印：

```
apt 镜像实测吞吐（字节/秒）：azure=45627172 archive=1045578
```

探测对象是 1.76 MB 的 `noble-updates/main/Packages.gz`。这么小的文件测的是连接建立，
不是持续吞吐 —— 结果它把已经退化的 azure 判成快 44 倍，于是「正确地」保留了默认镜像；
而几分钟以后，同一个 azure 下 bulk `.deb` 的实测速率只有约 50 kB/s
（`texlive-binaries` 8.5 MB 走掉 3 分钟）。小文件测速不只是测不出退化，它会主动把
慢镜像选进来。

**2. `apt_retry` 自己造出了 dpkg 死锁。** `MT5700M` job 的日志形态：

```
E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process using it?
Waiting for cache lock: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 10001 (apt)...
```

从 12:54 起连续 3 轮、约 17 次等待，13:23 才 exit 1，空烧近一小时。根因是
`timeout --kill-after=30 "$tmo" sudo -E apt ...` 这个顺序：`timeout` 是 `sudo` 的父进程，
超时信号发给 `sudo` 所在的进程组；`sudo` 收到 SIGKILL 后已经没机会再向子进程转发信号，
它拉起的 `apt` 于是成孤儿继续跑、继续持有 `lock-frontend`。此后每一次重试都必然卡在锁上
—— 重试机制本身让失败从「慢」变成了「死锁」。`init_build_environment` 的三轮重试同理。

**3. init 脚本仍走 `bash <(curl ...)`。** curl 卡住或失败时，进程替换喂给 bash 的是空内容，
bash 以 0 退出，这一步反而「成功」，缺依赖要到几小时后的编译阶段才暴露。

### 变更

- **`Select Apt Mirror` 换测速目标**：改用 `universe/binary-amd64/Packages.xz`
  （15.0 MB，apt 自身要下载，路径各版本都在），配合 `Range` 只取前 8 MB，比的是持续
  吞吐。50 kB/s 时 8 MB 需约 160 秒，必然顶到 `--max-time 25` 而现形；azure 正常时
  8 MB 不到 1 秒，判定保持默认。代号取自 `/etc/os-release`，runner 换版后若目标 404，
  两边都测到 0，退回「保持默认」，属安全降级而非误切换。
- **切换镜像后补一次 `apt -yqq update`**：否则后续 apt 仍按旧镜像取回的索引解析依赖。
- **`apt_retry` 与 init 重试都改为 `sudo` 在前、`timeout` 在后**：这样 `timeout` 与
  它拉起的 `apt` 同属一个进程组，SIGTERM/SIGKILL 能真正命中 `apt`，不再留下持锁孤儿。
  失败路径上加 `pgrep -a apt`，下次再出问题能直接看到持锁者而不必反推。
- **init 脚本先落盘再执行**：`curl -fsSL --retry 3 --connect-timeout 30 --max-time 120`
  下载后 `wc -c` 校验非空，再由 `sudo -E timeout --kill-after=30 900` 执行；
  已下载成功时后续重试不重复取脚本。
- **`99marvis-timeouts` 保持不变**：`DPkg::Lock::Timeout "120"` 本来就是对的，
  问题出在持锁者根本不该被自己造出来。

未删步骤、未放宽校验、未改编译参数与缓存键。

## [2026-11-06] 修复上游 apt 镜像吞吐退化导致的构建中断

### 背景

2026-11-06 的定时构建（`MTK-AUTO`，run 42142746141）两个 job 全部失败，
失败点为第 4 步 `Initialization Environment`，GitHub 给出的结论是
`The hosted runner lost communication with the server`。

取证过程与事实：

1. 失败 job 的日志端点返回 `404 The specified blob does not exist.`
   （整个运行的日志归档是 22 字节的空 zip），即 runner 在步骤执行中被环境回收，
   日志从未上传；结论横幅也不在 REST API 的 check-runs `output` 中，由运行页渲染。
2. 同日三个仓库（`OpenWRT-CI`、`H5000M-CI-Qmodem`、本仓库）的定时编译全部失败，
   上游模板仓库 `VIKINGYFY/OpenWRT-CI` 同为该结论，短任务 `Auto-Clean` 正常，
   04:53 之后的其他仓库构建也正常 → 不是 GitHub 全局故障。
3. 运行镜像未变化（`20261101.360` / runner 2.338.2，与 11-04、11-05 一致），
   排除镜像回归；11-05 同一步骤耗时 5 分 25 秒（01:12:15→01:17:40），
   当天却卡了 70–143 分钟。
4. 取消（cancel）可让 GitHub 上传已产生的部分日志；据此取到同款初始化步骤的实时输出现场：

   ```
   11:20:28 [INFO] Installing dependencies...
   11:20:29 Need to get 47.1 MB of archives.
   11:19:26 Ign:2 http://azure.archive.ubuntu.com/ubuntu noble-updates/main amd64 libapt-pkg6.0t64 ...
   11:28:08 Need to get 661 MB of archives.
   11:33:10 Ign:9 ... openjdk-21-jre-headless amd64 21.0.12.1+1-1~24.04.4
   11:38:15 Ign:32 ... texlive-binaries amd64 2023.20230311.66589-9build3
   11:48:22 Ign:34 ... texlive-fonts-recommended all 2023.20240207-1
   11:51:02 Ign:36 ... texlive-latex-base all 2023.20240207-1
   11:58:18 ##[error]The operation was canceled.
   ```

   30 分钟只下到第 36 个包（共 303 个、661 MB），换算吞吐约 2–4 MB/min，
   且 apt 反复把失败的包标成 `Ign:` 再重试 → 初始化步骤实际需要数小时。

根因：runner 默认镜像 `azure.archive.ubuntu.com` 当天吞吐骤降。runner 镜像内置的
`/etc/apt/apt-mirrors.txt` 是 `azure(priority:1) → archive(priority:2) → security(priority:3)`
的**优先级回退**列表，apt 只在镜像报错时降级，**镜像"慢"不会触发降级**，
于是上游 `init_build_environment.sh` 的 661 MB 依赖安装被拖到数小时，
最终 runner 与 GitHub 失联。

### 变更

- `.github/workflows/WRT-CORE.yml`：新增 `Select Apt Mirror` 步骤（5 分钟上限）。
  实测 `azure` 与 `archive.ubuntu.com` 下载同一索引文件的吞吐，
  仅当 `azure < 300 kB/s` 且 `archive` 至少快一倍时，把 `/etc/apt/apt-mirrors.txt`
  改成 `archive(priority:1)`，并对硬编码了 azure 的 sources 做等价替换；
  吞吐正常的日子不改变任何现有配置。
- 同文件：`Initialization Environment` 增加 `timeout-minutes: 60`（正常 5~6 分钟），
  job 增加 `timeout-minutes: 300`。异常时在可观测时间窗内失败并保留日志，
  不再出现"烧掉 1.5–2.5 小时且日志为空"的不可诊断状态。
- 同文件：`apt full-upgrade` 单次超时 1800s → 600s、`init_build_environment.sh`
  单次超时 1800s → 900s（各 3 次重试），把最坏耗时压到步骤上限之内；
  系统升级本就不是编译必需项，失败仍按原逻辑修复 dpkg 后继续。

### 影响范围

`MTK-AUTO.yml` 与 `WRT-BUILD.yml` 都复用 `WRT-CORE.yml`，两处构建入口均生效。
`OpenWRT-CI`、`H5000M-CI-Qmodem` 是独立仓库，本次未改动。

## [2026-10-31] 默认主题切换为 luci-theme-vantage（Aurora 保留为可选）

### 背景

上游 VIKINGYFY/OpenWRT-CI 已把默认主题从 aurora 换成 `anothaDev/luci-theme-vantage`。
本仓库同步：`WRT_THEME` 改为 vantage，同时保留 Aurora——
`luci-theme-aurora` + `luci-app-aurora-config` 继续编入固件，只取消其默认地位，
用户可在「系统 → 语言和界面」切回。

与"只改一行 WRT_THEME"相比，保留旧主题后有两处必须显式处理：

1. 原脚本固定拼 `CONFIG_PACKAGE_luci-app-$WRT_THEME-config`，对 vantage 会得到
   不存在的 `luci-app-vantage-config`；该类符号在 defconfig 阶段被静默丢弃，
   使 `.config` 与真实产物不一致（QModem 仓库同款代码配有
   `check_defconfig.py` 硬断言，会直接判失败）。
2. `luci-theme-bootstrap → luci-theme-$WRT_THEME` 的集合依赖替换只保证"主题被安装"，
   默认样式实际由 `/etc/config/luci` 的 `luci.main.mediaurlbase` 决定；该文件是
   conffile，sysupgrade 保留旧配置时仍为 `/luci-static/aurora`，而主题自带的
   `30_luci-theme-*` 脚本仅在主题首次注册时才写该值，升级路径不会切换。

### 变更

- `Scripts/Packages.sh`：新增 `UPDATE_PACKAGE "vantage" "anothaDev/luci-theme-vantage"
  "main"`（仓库内含 `luci-theme-vantage/` 与 `luci-app-vantage/` 两个包子目录，
  克隆到 `package/luci-theme-vantage` 后由 buildroot 递归扫描注册）。
  aurora / aurora-config 两行不变。
- `Scripts/Settings.sh`：主题配套包改为白名单映射（aurora →
  `luci-app-aurora-config`、vantage → `luci-app-vantage`、argon →
  `luci-app-argon-config`）；`WRT_THEME != aurora` 时追加 aurora 两个包以保留可选；
  新增「默认主题种子」段，生成 `files/etc/uci-defaults/40-luci-default-theme`
  （排在 `30_luci-theme-*` 之后），首启动把 `mediaurlbase` 指向
  `/luci-static/$WRT_THEME`，并用 `luci.main.theme_seeded` 记录已种子的默认主题，
  同一代主题不重复覆盖、用户自选主题不被升级重置。
- `Scripts/Handles.sh`：新增 vantage 进度条标签字体修复
  （`anothaDev/luci-theme-vantage#52`，与上游 CI 同一 sed）：`.cbi-progressbar::before`
  的 mono 字体改为继承正文字体，避免中文/窄屏下取值被截断；命中与否均写日志，
  上游已修正时自动跳过。
- `.github/workflows/MTK-AUTO.yml`、`.github/workflows/WRT-BUILD.yml`：
  `WRT_THEME: aurora` → `vantage`。
- `index.html`：首页特性标签 `UI: Aurora 极简主题` → `UI: Vantage 主题`。

### 验证

- Settings.sh 主题段在 `vantage` / `aurora` / `argon` 三组取值下实跑：
  vantage 输出四行（主题 + 仪表盘 + aurora 两项）；aurora 与改动前逐行一致；
  argon 输出主题 + aurora 两项。
- 种子脚本以桩 `uci` 复现三种情形（未种子 / 已种子 / 主题未编入），写操作与预期一致。
- vantage CSS 补丁对本仓库当前上游（v1.0.11）做 dry-run：仅目标 `font:` 一行被替换。

## [2026-10-30] 修复 homeproxy ucode 模块导出缺失（hasForceProxyRules）

### 背景

`Scripts/homeproxy/generate_client.uc` 覆盖上游 `luci-app-homeproxy` 的同名
脚本，该版本在 `import { ... } from 'homeproxy'` 中引入了
`hasForceProxyRules`，并用它决定 `bypass_mainland_china` 模式是否启用
geoip-cn 快速旁路。本仓库当前未覆盖该脚本，但一旦后续引入覆盖版
`generate_client.uc`，同样的错配会立刻出现，`homeproxy.uc` 仍来自 `VIKINGYFY/packages`，
其中并未导出该符号，构建出的固件在服务启动与订阅更新阶段直接抛：

    Syntax error: Module /etc/homeproxy/scripts/homeproxy.uc does not export 'hasForceProxyRules'

客户端配置因此无法生成，`/var/run/homeproxy/sing-box-c.json` 缺失，
代理全面失效，订阅更新以 exit code 2 退出。

### 变更

- `Scripts/Handles.sh`：在 homeproxy 资源预设段之后新增幂等防御逻辑，
  仅当 `generate_client.uc` 引用该符号且 `homeproxy.uc` 未导出时才追加
  实现；上游补齐或未启用覆盖时该段自动跳过。

### 验证

修复后 `ucode -L /etc/homeproxy/scripts -e 'import { hasForceProxyRules } from "homeproxy"'`
导入通过；`sing-box check` 无 error；无 Proxy List 时
`route_exclude_address_set` 正确输出 `["geoip-cn"]`（快速旁路生效）；
代理与直连均正常。

## [2026-10-28] UPnP 插件改用 VIKINGYFY/packages 源（miniupnpd + luci-app-upnp）

### 背景

上游 VIKINGYFY/OpenWRT-CI 于 2026-10-27 把 `miniupnpd` 与 `luci-app-upnp`
纳入其 `VIKINGYFY/packages` 仓库，并在 viking 包组中启用。本仓库同步该
做法，UPnP（IGD / PCP / NAT-PMP 端口自动映射）改用同一维护源，与上游
保持一致的版本节奏与补丁基线。

**未涉及主题**：`MTK-AUTO.yml` / `WRT-BUILD.yml` 的 `WRT_THEME: aurora`、
`Scripts/Packages.sh` 的 aurora / aurora-config 源、`Scripts/Handles.sh`
的 aurora 菜单样式修复均原样保留，本次不做主题相关改动。

### 变更

- `Scripts/Packages.sh`：viking 包组清理名单追加 `miniupnpd`、
  `luci-app-upnp`：

  ```diff
  -UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac sing-box luci-app-homeproxy luci-app-timewol luci-app-wolplus luci-app-wolultra"
  +UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac miniupnpd sing-box luci-app-homeproxy luci-app-timewol luci-app-upnp luci-app-wolplus luci-app-wolultra"
  ```

  该名单在克隆前会 `rm -rf` 掉 `../feeds/luci/`、`../feeds/packages/` 下所有
  名字匹配的目录，因此 immortalwrt feeds 自带的 `miniupnpd` /
  `luci-app-upnp` 会被清除，改用 viking 源。

### 说明

- 编译配置无需改动：`Config/GENERAL.txt` 已有
  `CONFIG_PACKAGE_luci-app-upnp=y`（在「新增实用插件」区块内），且
  `Custom Settings` 步骤在非 TEST 模式下必叠加 GENERAL.txt；
- `miniupnpd` 不需要单独选中：`luci-app-upnp` 的
  `LUCI_DEPENDS:=+luci-base +miniupnpd +rpcd-mod-ucode` 会自动带出；
  viking 源用 `PROVIDES:=miniupnpd` + `DEFAULT_VARIANT:=1` 定义两个变体
  （`miniupnpd-iptables` / `miniupnpd-nftables`），依赖 `+miniupnpd` 会解析
  到默认的 **nftables 变体**，与本仓库 `kmod-nft-*`（firewall4）栈一致；
- 版本约束自洽：`luci-app-upnp` 的
  `LUCI_EXTRA_DEPENDS:=miniupnpd (>=20261027-r7)` 与同源 `miniupnpd` 的
  `PKG_VERSION:=20261027` / `PKG_RELEASE:=7` 完全吻合，不会在 world 安装
  阶段因约束不满足而失败（与 homeproxy 的 sing-box ≥1.15.0 那类问题同构，
  此处不存在）；
- 与现有 feed 补丁修复的兼容：`WRT-CORE.yml` 的「Update Feeds」步骤中有一处
  针对 feeds 的 `feeds/packages/net/miniupnpd/patches/020-descr-filter-fix.patch`
  删除。该步骤带 `-f` 守卫，而本改动会在后续「Custom Packages」阶段删除整个
  feeds miniupnpd 目录，故它自动退化为 no-op，**不会报错、无需删除**，
  作为以后切回 feeds 源时的保险保留；
- viking 源的 `miniupnpd/patches/` 仅含 `010-upnp-igdv2-compat.patch` 与
  `900-miniupnpd-format-xml-to-make-some-app-happy.patch`，不是 2.3.11 那次
  失配的 020（两个补丁已在兄弟仓库独立复验整链可应用），不会复现补丁失配
  导致的编译中断；
- `index.html`（介绍页）本就含 UPnP 标签，无需同步修改。

## [2026-10-26] 风扇温控按固件分流：MT5700 固件换用 LianXia233 Rust 重写版，MT5700M 固件沿用 FAN789 原版

### 背景

`MT5700` 固件（新模组插件 `luci-app-mt5700`）原先的风扇插件是
`FAN789/luci-app-h5000m-fancontrol`（v2.1.1，shell 控制器），模组温度只能靠本仓库
随包注入的 `mt5700-temp-bridge`（`INJECT_MT5700_TEMP_BRIDGE`）经 ubus 桥接。
[LianXia233/luci-app-h5000m-fancontrol](https://github.com/LianXia233/luci-app-h5000m-fancontrol)
是其 v3.x 演进分支：控制器重写为零依赖 Rust 静态二进制（rust-lld + musl 自包含
链接），并**内置** at-webserver 温度桥接——每 30 秒经本地 RPC（`127.0.0.1:8765`，
newline-JSON，与 at-webserver 默认 `websocket_port` 一致、默认无 auth_key）下发
`AT^CHIPTEMP?`，取 12 路峰值按旧格式写回 `/var/run/mt5700m/temperature`。

`MT5700M` 固件（旧模组插件 `luci-app-mt5700m`）保持原有组合不动：模组温度由
`mt5700m-manager` 写入同一文件，风扇插件沿用 FAN789 原版 v2.1.1（纯 shell）。
两个风扇仓库**包名相同**，同一 package 树只能存在一套（OpenWrt 会报重复包定义），
故按 `WRT_MODEM` 在每个矩阵作业里条件克隆其一。

### 变更

- `Scripts/Packages.sh`：
  - 风扇插件 clone 按 `WRT_MODEM` 分流：`MT5700` → `LianXia233/luci-app-h5000m-fancontrol`，
    `MT5700M` → 沿用 `FAN789/luci-app-h5000m-fancontrol`。包名与依赖不变
    （`+luci-base +kmod-hwmon-pwmfan`），`Config/GENERAL.txt` 的启用项两套通用。
  - 移除 `INJECT_MT5700_TEMP_BRIDGE()` 及其调用（新版风扇控制器经 RPC 直连后端，
    桥接职责已内置；该注入本来就只随 `luci-app-mt5700` 打包，MT5700M 固件从未包含）。
  - 新增 `PREPARE_FANCONTROL_PREBUILT()`（仅 MT5700 作业执行）：与
    `PREPARE_MT5700_PREBUILT()` 同思路，把 `src/Makefile` 的 `compile` 目标改成
    「有 CI 预编译产物直接装、否则回退 cargo」，并把解析期「cargo 缺失即
    `$(error)`」降级为 `$(warning)`——否则 buildroot 阶段 Makefile 在解析时就失败，
    预编译分支根本走不到；ELF 架构校验两个分支共用。
  - 克隆结构校验按来源分支（新版要求 `src/` 工程与 uci-defaults v3、不得有 shell
    控制器；旧版要求 shell 控制器与 uci-defaults v2、不得有 `src/`），并把版本与
    来源写入 `H5000M_FANCONTROL_VERSION`（GITHUB_ENV，供 Release Notes 引用）。
- `.github/workflows/WRT-CORE.yml`：
  - 「Smoke Test luci-app-mt5700」：移除温度桥接三件套的检查项（注入已删除）。
  - 新增「Smoke Test luci-app-h5000m-fancontrol」（仅 `WRT_MODEM != 'MT5700M'`）：
    结构校验（含预编译注入标记与 cargo 告警降级）、shell 语法、LuCI JS 语法与
    浏览器级渲染冒烟、i18n 完整性、JSON 元数据、上游打包红线 / uci-defaults 迁移 /
    内核热保护静态检查（取自新版上游 CI，无需 Rust）。
  - 「Cross Compile Rust Backend」→「Cross Compile Rust Backends」，条件保持
    `WRT_TEST != 'true' && WRT_MODEM != 'MT5700M'`：步骤内先跑新版风扇控制器的
    上游 `cargo test`，再交叉编译出预编译产物（零依赖 crate，无需 zig）；随后照旧
    zig 链接编译 at-webserver。MT5700M 构建全程无 Rust，步骤整体跳过（与原先一致）。
  - Release Notes 增加「风扇插件版本」行（带来源标注，如 `3.2.0（LianXia233）` /
    `2.1.1（FAN789）`）。
- `Config/GENERAL.txt` / `Config/MT5700M.txt`：注释说明风扇来源按固件分流。
- `README.md` / `index.html`：风扇章节改为两套来源对照表；温度联动改为新版控制器
  内置 RPC 桥接的描述；鸣谢同步。

### 不兼容说明

- **MT5700M 固件：无行为变化**（模组插件、风扇插件 v2.1.1、温度数据流全保持原样；
  唯一差异是构建日志与 Release Notes 现在会记录风扇插件版本）。
- MT5700 固件风扇插件 2.x → 3.x：UCI 选项集兼容，随包
  `uci-defaults/91-h5000m-fancontrol-v3` 按 `schema_version` 迁移（仅补缺、不覆盖
  已有值）；服务名 `/etc/init.d/h5000m-fancontrol`、菜单入口
  `admin/system/h5000m_fancontrol`、温度缓存路径与 `key=value` 状态输出（含全部
  2.x 键）均不变，旧固件 sysupgrade 无感切换。
- `mt5700-temp-bridge` 三件套不再随固件发布（职责并入新版风扇控制器）；若有脚本
  依赖它，需改为读 `/var/run/mt5700m/temperature` 或直接调用 at-webserver RPC。
- MT5700 固件的风扇控制器现为架构相关包（不再是 `all`），依赖 CI 预编译注入。

### 验证

- `bash -n Scripts/Packages.sh` 通过；`PREPARE_FANCONTROL_PREBUILT` 对真实克隆的
  LianXia233/luci-app-h5000m-fancontrol 实测：cargo `$(error)` 降级 1 处、`compile`
  目标替换 1 处、重复执行幂等跳过，生成 Makefile 的 recipe 为真实 TAB、LF 行尾。
- 克隆结构校验两分支均用本地克隆实测：`WRT_MODEM=MT5700` 对 LianXia233 仓库通过、
  对 FAN789 仓库正确报缺 `src/` 工程；`WRT_MODEM=MT5700M` 对 FAN789 仓库通过、
  对 LianXia233 仓库正确报缺 shell 控制器（防 clone 错来源）。
- 上游 `tests/test-packaging.sh`（含 src/Makefile 断言）、`test-uci-defaults.sh`、
  `test-kernel-safety.sh` 在注入后的新版克隆上全部通过。
- workflow YAML 解析通过；smoke test 与 Rust 预编译步骤的 `WRT_MODEM` 条件与
  Packages.sh 的条件克隆分支一一对应。

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
