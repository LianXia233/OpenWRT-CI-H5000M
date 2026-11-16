#!/bin/bash
# SPDX-License-Identifier: MIT
# 按机型生成 luci-app-online-upgrade 的出厂预设（/etc/config/online-upgrade）
#
# 为什么构建期生成而不是提交静态文件：升级源里「哪个 Release / 哪个资产」
# 取决于运行期变量 —— 本仓库每次构建固定产出两套固件（WRT_MODEM=MT5700 /
# MT5700M），Release tag 与资产名都带模组标识：
#   tag   : MEDIATEK-WIFI-YES-VIKINGYFY-owrt-<MODEM>-<YY.MM.DD-HH.MM.SS>（格式保持不变）
#   资产  : <device>-<MODEM>-<YYYYMMDD>-sysupgrade.bin
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
# SHA256 不写进预设：expected_sha256 是「本次 Release 的固定值」，出厂固化会让
# 之后每个版本都拿旧哈希去比对。WRT-CORE 改为把每个固件的 sha256sum 写进
# Release 正文，上游 github.rs 的 find_sha256_in_text 会按资产名自动取到，
# 既不新增资产、也不占用 UCI 键。
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
# 产物名里的机型取设备定义的 DEVICE_MODEL（如 H5000M），与 WRT-CORE
# 「Package Firmware」一致；解析不到时退回 OpenWrt 设备名。
MODEL=$(grep -rhA10 "^define Device/$DEVICE_NAME$" target/linux/*/image/*.mk 2>/dev/null \
	| sed -n 's/^[[:space:]]*DEVICE_MODEL[[:space:]]*:=[[:space:]]*//p' | head -1)
MODEL="${MODEL:-$DEVICE_NAME}"

# 资产名规则取自 WRT-CORE「Package Firmware」（v2.7 三仓库统一）：
#   <机型>-<模组插件>-<架构>-<YY.MM.DD>-<镜像类型>.<扩展名>
# 实测：H5000M-MT5700-aarch64-26.11.16-sysupgrade.bin
# 用「机型 + 模组 + 架构 + 点分日期 + 镜像类型」锚定：
#   - 架构段声明架构，供升级插件 compat 判定（缺了只能判未声明）；
#   - 点分日期是日期型版本，供 version::pick 比较新旧；
#   - 模组标识两侧带连字符，MT5700 正则不会命中 MT5700M。
WRT_ARCH="${WRT_ARCH:-aarch64}"
PATTERN="^${MODEL}-${WRT_MODEM}-${WRT_ARCH}-[0-9.]+-sysupgrade\\.bin\$"

# v2.7 统一规则：TAG 追踪模式与过滤正则解耦（与另两个 CI 仓库一致）。
#   tag      = latest
#   tag_rule = ^<TAG_PREFIX>
BRANCH_RE="${WRT_BRANCH//./\\.}"
if [ -n "$WRT_INFO" ] && [ -n "$BRANCH_RE" ]; then
	TAG_PREFIX="${WRT_CONFIG}-${WRT_INFO}-${BRANCH_RE}-${WRT_MODEM}-"
else
	TAG_PREFIX="${WRT_MODEM}-"
fi
TAG_RULE="^${TAG_PREFIX}"
TAG='latest'

mkdir -p "$(dirname "$TARGET")"
{
	printf '# 出厂预设：构建期由 Scripts/OnlineUpgradePreset.sh 按机型生成，勿手改\n'
	printf 'config online-upgrade %s\n' "'settings'"
	printf "\toption repo '%s'\n" "$UPGRADE_REPO"
	printf "\toption tag '%s'\n" "$TAG"
	printf "\toption tag_rule '%s'\n" "$TAG_RULE"
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
EXPECT_KEYS=11
GOT_KEYS=$(grep -c '^[[:space:]]*option ' "$TARGET" || true)
if [ "$GOT_KEYS" -ne "$EXPECT_KEYS" ]; then
	echo "::error::${TARGET} 生成异常：期望 ${EXPECT_KEYS} 个 option，实际 ${GOT_KEYS}"
	exit 1
fi
for KV in "repo '${UPGRADE_REPO}'" "tag '${TAG}'" "tag_rule '${TAG_RULE}'" "firmware_pattern '${PATTERN}'"; do
	grep -qF "option ${KV}" "$TARGET" || {
		echo "::error::${TARGET} 的 ${KV} 与推导值不一致"
		exit 1
	}
done

# 正则自检：构造示例产物名 / 示例标签，确认两条规则真能命中，
# 避免上游 Regex::new 编译失败或锚点写错导致设备端 OTA 找不到固件。
SAMPLE="${MODEL}-${WRT_MODEM}-${WRT_ARCH}-26.11.09-sysupgrade.bin"
if [[ ! "$SAMPLE" =~ $PATTERN ]]; then
	echo "::error::firmware_pattern 未匹配示例产物 ${SAMPLE}（规则=${PATTERN}）"
	exit 1
fi
if [ -n "$WRT_INFO" ] && [ -n "$BRANCH_RE" ]; then
	SAMPLE_TAG="${WRT_CONFIG}-${WRT_INFO}-${WRT_BRANCH}-${WRT_MODEM}-26.11.09-18.27.39"
	if [[ ! "$SAMPLE_TAG" =~ $TAG_RULE ]]; then
		echo "::error::tag_rule 正则未匹配示例标签 ${SAMPLE_TAG}（规则=${TAG_RULE}）"
		exit 1
	fi
fi

# ---- 固件版本标记：自动注入 /etc/online-upgrade/firmware-version ----
# luci-app-online-upgrade 读取它作为本机固件版本的强依据（basis_score 85 起），
# 避免只用构建时间/过期锚点推断而显示「判定依据较弱」。内容 YY.MM.DD 与
# Release tag、资产名同源；每天构建自动更新，即「自动升版」，无需人工改版本号。
# 三仓库变量名不统一：本仓库/Qmodem 导出 WRT_DATE_DOT，OpenWRT-CI 导出 WRT_DATE_SHORT。
# 这里逐个尝试并校验 YY.MM.DD 形状，都缺失时按 UTC+8 现算兜底。
FW_VERSION=""
for cand in "${WRT_DATE_DOT:-}" "${WRT_DATE_SHORT:-}" "$(TZ=UTC-8 date +'%y.%m.%d')"; do
	case "$cand" in
		[0-9][0-9].[0-9][0-9].[0-9][0-9]) FW_VERSION="$cand"; break ;;
	esac
done
if [ -z "$FW_VERSION" ]; then
	echo "::error::无法生成固件版本标记（期望 YY.MM.DD），停止构建"
	exit 1
fi
FW_MARKER_DIR="./files/etc/online-upgrade"
FW_MARKER="$FW_MARKER_DIR/firmware-version"
mkdir -p "$FW_MARKER_DIR"
printf '%s\n' "$FW_VERSION" > "$FW_MARKER"
# 自检：标记文件必须存在且内容恰为版本号，否则红掉而不是带坏标记编译。
[ "$(cat "$FW_MARKER")" = "$FW_VERSION" ] || {
	echo "::error::${FW_MARKER} 写入失败或内容不符（期望 ${FW_VERSION}）"
	exit 1
}

echo "==> 在线升级预设：配置=${WRT_CONFIG} 设备=${PLATFORM}/${DEVICE_NAME} 模组=${WRT_MODEM}"
echo "    tag=${TAG}"
echo "    tag_rule=${TAG_RULE}"
echo "    firmware_pattern=${PATTERN}"
echo "    固件版本标记=${FW_MARKER} = ${FW_VERSION}"
