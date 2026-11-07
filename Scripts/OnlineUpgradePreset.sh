#!/bin/bash
# SPDX-License-Identifier: MIT
# 按机型生成 luci-app-online-upgrade 的出厂预设（/etc/config/online-upgrade）
#
# 为什么构建期生成而不是提交静态文件：升级源里「哪个 Release / 哪个资产」
# 取决于运行期变量 —— 本仓库每次构建固定产出两套固件（WRT_MODEM=MT5700 /
# MT5700M），Release tag 与资产名都带模组标识（实测 2026-11-07 产物）：
#   tag   : MEDIATEK-WIFI-YES-VIKINGYFY-owrt-<MODEM>-<YY.MM.DD-HH.MM.SS>
#   资产  : <platform>-<device>-squashfs-sysupgrade-<SOURCE>-<BRANCH>-wifi-yes-<MODEM>-<date>.bin
# 静态文件无法同时覆盖两套，且设备型号/平台若变化也要跟着改；构建期生成
# 则与产物一一对应。
#
# 落点遵循仓库既有 overlay 约定：$(TOPDIR)/files 会被原样并入 rootfs，
# Scripts/Settings.sh 也已经用 ./files/etc/uci-defaults 生成主题种子。
# 因此这里写 ./files/etc/config/online-upgrade，覆盖包自带的同名 conffile，
# 首次开机即为对应机型的升级源；插件自带 /lib/upgrade/keep.d 条目会在
# sysupgrade 时保留该配置。
#
# 键名全部取自上游代码，不是猜测：
#   rust/src/uci.rs                 const BASE = "online-upgrade.settings"
#   rust/src/github.rs              repo / tag / proxy / firmware_pattern / min_size_mb / github_token
#   rust/src/downloader.rs          dl_workers / dl_chunk_mb / dl_stall_sec / dl_retries
#   rust/src/upgrade.rs             expected_sha256（自定义校验值，留空则用 Release 资产或正文里的 sha256）
# 上游默认配置与 README 里的 enabled / keep_config 在本版本 Rust 与 rpcd 代码中
# 均未被读取，故不写入预设，避免产生「配了却不起作用」的假象。
#
# 用法（在 OpenWrt 源码树根目录，defconfig 之前由 Settings.sh 调用）：
#   Scripts/OnlineUpgradePreset.sh

set -euo pipefail

WRT_CONFIG="${WRT_CONFIG:-}"
WRT_MODEM="${WRT_MODEM:-MT5700}"
WRT_INFO="${WRT_INFO:-}"
WRT_BRANCH="${WRT_BRANCH:-}"
WRT_SOURCE="${WRT_SOURCE:-}"

TARGET="./files/etc/config/online-upgrade"
UPGRADE_REPO="${ONLINE_UPGRADE_SOURCE_REPO:-LianXia233/OpenWRT-CI-H5000M}"
# 本脚本的工作目录是 OpenWrt 源码树根（./wrt），机型配置片段在仓库根 Config/ 下
CFG_FILE="${GITHUB_WORKSPACE:-.}/Config/${WRT_CONFIG}.txt"

# 包未选中时不生成预设：文件会随 files/ 打进固件，但设备上没有对应软件，
# 只会留下一个没人读的配置。Settings.sh 默认总会选中它，这里只是防御。
if [ -f ./.config ] && ! grep -q '^CONFIG_PACKAGE_luci-app-online-upgrade=y' ./.config; then
	echo "==> luci-app-online-upgrade 未选中，跳过升级预设生成"
	exit 0
fi

if [ -z "$WRT_CONFIG" ] || [ ! -f "$CFG_FILE" ]; then
	echo "::warning::无法读取 Config/${WRT_CONFIG}.txt，跳过升级预设生成"
	exit 0
fi

# 设备与平台从该机型的 .config 片段解析，不另立机型清单（避免两处维护）：
#   MULTI_PROFILE=n 时为 CONFIG_TARGET_<platform>_DEVICE_<device>=y
#   MULTI_PROFILE=y 时为 CONFIG_TARGET_DEVICE_<platform>_DEVICE_<device>=y
DEVICE_SYM=$(grep -oP '^CONFIG_TARGET_\K[A-Za-z0-9_]+(?==y)' "$CFG_FILE" \
	| grep '_DEVICE_' | head -1)
if [ -z "$DEVICE_SYM" ]; then
	echo "::warning::Config/${WRT_CONFIG}.txt 未包含设备符号（CONFIG_TARGET_*_DEVICE_*=y），跳过升级预设生成"
	exit 0
fi
PLATFORM="${DEVICE_SYM%%_DEVICE_*}"
PLATFORM="${PLATFORM#DEVICE_}"
DEVICE_NAME="${DEVICE_SYM##*_DEVICE_}"
# OpenWrt 产物把 target 与 subtarget 用连字符连接（mediatek_filogic → mediatek-filogic）
TARGET_DASH="${PLATFORM//_/-}"

# 资产名规则取自 WRT-CORE「Package Firmware」：
#   NEW_FILE = <固件基名去掉 immortalwrt 前缀> - WRT_INFO - WRT_BRANCH -
#              WRT_WIFI - WRT_MODEM - WRT_DATE . <EXT>
# 实测：mediatek-filogic-hiveton_h5000m-squashfs-sysupgrade-
#       VIKINGYFY-owrt-wifi-yes-MT5700-26.11.07-11.58.26.bin
# 因此用「平台 + 设备 + 任意镜像类型 + 模组标识 + 日期 + .bin」锚定：
#   - 结尾 .bin 排除同批上传的 .manifest / Config-*.txt；
#   - 模组标识两侧都带连字符，MT5700 的正则不会命中 MT5700M
#     （后者是 -MT5700M-，最后一个字符是 M，不构成 -MT5700-）。
PATTERN="^${TARGET_DASH}-${DEVICE_NAME}-.*-${WRT_MODEM}-.*\.bin\$"

# tag 语义来自 rust/src/github.rs：latest 取最新 Release，latest@<正则>
# 只在 tag 名匹配该正则的 Release 里找最新。这里按「配置-来源-分支-模组」
# 归组，保证 MT5700 固件不会从 MT5700M 组里取错产物（同理反向）。
# 缺 WRT_INFO / WRT_BRANCH（本地手跑）时退化为只按模组过滤，仍不会跨模组。
if [ -n "$WRT_INFO" ] && [ -n "$WRT_BRANCH" ]; then
	TAG_PREFIX="${WRT_CONFIG}-${WRT_INFO}-${WRT_BRANCH}-${WRT_MODEM}-"
else
	TAG_PREFIX="${WRT_MODEM}-"
fi
TAG="latest@^${TAG_PREFIX}"

mkdir -p "$(dirname "$TARGET")"
{
	printf '# 出厂预设：构建期由 Scripts/OnlineUpgradePreset.sh 按机型生成，勿手改\n'
	printf 'config online-upgrade %s\n' "'settings'"
	printf "\toption repo '%s'\n" "$UPGRADE_REPO"
	printf "\toption tag '%s'\n" "$TAG"
	printf "\toption firmware_pattern '%s'\n" "$PATTERN"
	printf "\toption min_size_mb '15'\n"
	printf "\toption proxy 'https://gh.acg2.mom/'\n"
	printf "\toption expected_sha256 ''\n"
	printf "\toption dl_workers '6'\n"
	printf "\toption dl_chunk_mb '4'\n"
	printf "\toption dl_stall_sec '30'\n"
	printf "\toption dl_retries '3'\n"
} > "$TARGET"

# 生成后自检：10 个键一个不少，且关键项与推导值一致。
# 任何一项不匹配都说明模板被改坏，直接红掉而不是带着坏预设编译。
EXPECT_KEYS=10
GOT_KEYS=$(grep -c '^[[:space:]]*option ' "$TARGET" || true)
if [ "$GOT_KEYS" -ne "$EXPECT_KEYS" ]; then
	echo "::error::${TARGET} 生成异常：期望 ${EXPECT_KEYS} 个 option，实际 ${GOT_KEYS}"
	exit 1
fi
for KV in "repo '${UPGRADE_REPO}'" "tag '${TAG}'" "firmware_pattern '${PATTERN}'"; do
	grep -qF "option ${KV}" "$TARGET" || {
		echo "::error::${TARGET} 的 ${KV} 与推导值不一致"
		exit 1
	}
done

echo "==> 在线升级预设：配置=${WRT_CONFIG} 设备=${PLATFORM}/${DEVICE_NAME} 模组=${WRT_MODEM}"
echo "    tag=${TAG}"
echo "    firmware_pattern=${PATTERN}"
