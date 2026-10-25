#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git"

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./$REPO_NAME/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f $REPO_NAME $PKG_NAME
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name，可选，pkg为从大杂烩中单独提取包名插件；name为重命名为包名"
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"

UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

#UPDATE_PACKAGE "athena-led" "unraveloop/JDC-AX6600-Athena-LED-Controller" "main"
UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac sing-box luci-app-homeproxy luci-app-timewol luci-app-wolplus luci-app-wolultra"

# 2026-10-23 移除 qmodem（FUjr/QModem）clone：
# QModem 与 MT5700M 模组插件会争抢同一 AT 串口，并存存在误操作风险；
# 本固件 GENERAL.txt 亦从未启用 luci-app-qmodem，移除 clone 不影响产物，
# 仅减少每次构建的 clone 耗时与 package 树体积。如需恢复，取消下一行注释：
#UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"

# ===== sing-box 过时补丁清理（2026-09-24 定时构建失败根因）=====
# VIKINGYFY/packages 的 sing-box 自带 patches/100-fix-dns-tcp-close.patch，它是针对
# 旧版 sing-box 的反向移植（引入上游从未合入的 HandleStreamDNSConnection）。当 feed 把
# sing-box 升到 1.15.0_alpha8 后，该补丁上下文已与上游源码（仍是 HandleStreamDNSRequest）
# 不匹配，OpenWrt 在 Build/Prepare 阶段应用补丁报 “Patch failed!” 并 Error 1，
# 进而令整个固件编译中断（今日定时构建失败即此因）。上游 immortalwrt/packages 的 sing-box
# 根本不携带该补丁也能正常构建，故这里在补丁确为旧版（内容含 HandleStreamDNSConnection）
# 时移除它，恢复构建。若 VIKINGYFY 后续刷新该补丁为适配新源码的版本，本规则因标记不匹配
# 而自动跳过，不会误删新版补丁。
FIX_SINGBOX_STALE_PATCH() {
	local PATCH="./packages/sing-box/patches/100-fix-dns-tcp-close.patch"
	[ -f "$PATCH" ] || { echo "sing-box: 无 100-fix-dns-tcp-close.patch，跳过"; return 0; }
	# 仅当补丁仍为旧版（引入未合入上游的 HandleStreamDNSConnection）时才移除
	if grep -q "HandleStreamDNSConnection" "$PATCH"; then
		rm -f "$PATCH"
		echo "sing-box: 移除过时补丁 100-fix-dns-tcp-close.patch（与 1.15.0_alpha8 源码不匹配）"
	else
		echo "sing-box: 100-fix-dns-tcp-close.patch 已非旧版，保留"
	fi
}
FIX_SINGBOX_STALE_PATCH

UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"

# H5000M 硬件配套插件
# 风扇控制（2026-10-26 起改用 LianXia233/luci-app-h5000m-fancontrol，FAN789
# 原版 v2.x shell 控制器的 Rust 重写分支）：v3.x 单包内含 LuCI 前端与零依赖
# Rust 控制器，且内置 at-webserver 温度桥接（每 30s 经 127.0.0.1:8765 RPC 取
# AT^CHIPTEMP? 峰值写 /var/run/mt5700m/temperature），无需本仓库再注入桥接；
# Rust 交叉编译适配见下方 PREPARE_FANCONTROL_PREBUILT 与结构校验。
UPDATE_PACKAGE "luci-app-h5000m-fancontrol" "LianXia233/luci-app-h5000m-fancontrol" "main"
UPDATE_PACKAGE "luci-app-h5000m-netmode" "FAN789/luci-app-h5000m-netmode" "main"

# ===== MT5700M 模组管理插件（2026-10-25，两套并存但同一固件只编译一套）=====
# 两套插件都 clone 到 package 树，具体编译哪一套由 Config/MT5700.txt（新插件）或
# Config/MT5700M.txt（旧插件）决定，WRT_MODEM 选择其一追加进 .config。
# 两者都独占 MT5700M 的 AT 串口（新插件由 Rust 后端持有串口，旧插件由
# mt5700m-transport 持有），同一份 .config 里绝不能同时启用，否则必然互相抢口、
# 随机出现「命令超时 / 模组无响应」。WRT-CORE.yml 在 make defconfig 之后强制校验
# 「两套主包只有一个为 y」，违反即失败。
#
# 旧插件 FAN789/luci-app-mt5700m：仓库顶层含 luci-app-mt5700m 与 mt5700m-transport
# 两个包，clone 后目录名 luci-app-mt5700m，被 immortalwrt 的 SCAN_DEPTH 正常扫描。
UPDATE_PACKAGE "luci-app-mt5700m" "FAN789/luci-app-mt5700m" "main"
# 新插件 LianXia233/luci-app-mt5700：该仓库顶层即包定义（Makefile + htdocs + po +
# root + src），单包内含 LuCI 前端与 Rust/Tokio 后端（at-webserver-rust），clone 后
# 目录名正好是包名，无需二次整理。
UPDATE_PACKAGE "luci-app-mt5700" "LianXia233/luci-app-mt5700" "main"

# ===== luci-app-mt5700 克隆结果校验与版本记录（2026-10-25）=====
# 上游仓库结构调整、文件改名或漏推时在此尽早失败，避免数小时后才在编译阶段暴露。
# 同时把版本号写入 GITHUB_ENV，供 Release Notes 引用。
MT5700_DIR="./luci-app-mt5700"
MT5700_REQUIRED="Makefile
src/Makefile
src/rust/Cargo.toml
src/rust/Cargo.lock
root/etc/init.d/at-webserver
root/etc/config/at-webserver
root/usr/share/rpcd/ucode/mt5700.uc
root/usr/share/luci/menu.d/luci-app-mt5700.json
root/usr/share/rpcd/acl.d/luci-app-mt5700.json
htdocs/luci-static/resources/view/at-webserver/network_status.js
po/zh_Hans/luci-app-mt5700.po"
MT5700_MISSING=""
while read -r MT5700_FILE; do
	[ -z "$MT5700_FILE" ] && continue
	[ -f "$MT5700_DIR/$MT5700_FILE" ] || MT5700_MISSING="$MT5700_MISSING $MT5700_FILE"
done <<< "$MT5700_REQUIRED"
if [ -n "$MT5700_MISSING" ]; then
	echo "ERROR: LianXia233/luci-app-mt5700 仓库结构异常，缺少:$MT5700_MISSING" >&2
	exit 1
fi
MT5700_VER=$(sed -n 's/^PKG_VERSION:=//p' "$MT5700_DIR/Makefile" | head -1)
MT5700_BACKEND_VER=$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$MT5700_DIR/src/rust/Cargo.toml" | head -1)
MT5700_INFO="plugin ${MT5700_VER} / backend ${MT5700_BACKEND_VER}"
echo "luci-app-mt5700 version: $MT5700_INFO"
[ -n "${GITHUB_ENV:-}" ] && echo "MT5700_VERSION=$MT5700_INFO" >> "$GITHUB_ENV"

# ===== luci-app-mt5700m（旧插件）克隆结果校验与版本记录 =====
# 旧插件不在本固件默认启用，但仍要保证：一旦改用 Config/MT5700M.txt，clone 出来的
# 两个包结构完整，否则会在编译阶段才报错。
MT5700M_DIR="./luci-app-mt5700m"
for MT5700M_FILE in \
	luci-app-mt5700m/Makefile \
	mt5700m-transport/Makefile \
	mt5700m-transport/src/transport.c \
	luci-app-mt5700m/root/usr/sbin/mt5700m-manager \
	luci-app-mt5700m/root/etc/init.d/mt5700m-manager \
	luci-app-mt5700m/po/zh_Hans/mt5700m.po; do
	if [ ! -f "$MT5700M_DIR/$MT5700M_FILE" ]; then
		echo "ERROR: FAN789/luci-app-mt5700m 仓库结构异常，缺少 $MT5700M_FILE" >&2
		exit 1
	fi
done
MT5700M_VER=$(sed -n 's/^PKG_VERSION:=//p' "$MT5700M_DIR/luci-app-mt5700m/Makefile" | head -1)
MT5700M_TRANSPORT_VER=$(sed -n 's/^PKG_VERSION:=//p' "$MT5700M_DIR/mt5700m-transport/Makefile" | head -1)
MT5700M_INFO="plugin ${MT5700M_VER} / transport ${MT5700M_TRANSPORT_VER}"
echo "luci-app-mt5700m version: $MT5700M_INFO"
[ -n "${GITHUB_ENV:-}" ] && echo "MT5700M_VERSION=$MT5700M_INFO" >> "$GITHUB_ENV"

# ===== luci-app-h5000m-fancontrol 克隆结果校验与版本记录（2026-10-26）=====
# 风扇插件 v3.x（LianXia233 Rust 重写版）换源后结构有变：新增 src/ Rust 工程与
# uci-defaults v3，root 下不再有 shell 控制器。上游结构调整、文件改名或漏推时
# 在此尽早失败，避免数小时后才在编译阶段暴露；同时把版本写入 GITHUB_ENV，
# 供 Release Notes 引用。
FANCONTROL_DIR="./luci-app-h5000m-fancontrol"
FANCONTROL_REQUIRED="Makefile
src/Makefile
src/Cargo.toml
src/Cargo.lock
src/.cargo/config.toml
src/src/main.rs
root/etc/config/h5000m_fancontrol
root/etc/init.d/h5000m-fancontrol
root/etc/uci-defaults/91-h5000m-fancontrol-v3
root/usr/sbin/h5000m-fancontrol-status
root/usr/share/luci/menu.d/luci-app-h5000m-fancontrol.json
root/usr/share/rpcd/acl.d/luci-app-h5000m-fancontrol.json
htdocs/luci-static/resources/view/h5000m/fancontrol.js
po/zh_Hans/h5000m-fancontrol.po"
FANCONTROL_MISSING=""
while read -r FANCONTROL_FILE; do
	[ -z "$FANCONTROL_FILE" ] && continue
	[ -f "$FANCONTROL_DIR/$FANCONTROL_FILE" ] || FANCONTROL_MISSING="$FANCONTROL_MISSING $FANCONTROL_FILE"
done <<< "$FANCONTROL_REQUIRED"
if [ -n "$FANCONTROL_MISSING" ]; then
	echo "ERROR: LianXia233/luci-app-h5000m-fancontrol 仓库结构异常，缺少:$FANCONTROL_MISSING" >&2
	exit 1
fi
FANCONTROL_VER=$(sed -n 's/^PKG_VERSION:=//p' "$FANCONTROL_DIR/Makefile" | head -1)
echo "luci-app-h5000m-fancontrol version: $FANCONTROL_VER"
[ -n "${GITHUB_ENV:-}" ] && echo "H5000M_FANCONTROL_VERSION=$FANCONTROL_VER" >> "$GITHUB_ENV"

# ===== 深度适配：让包在 buildroot 内使用 CI 预编译的 Rust 后端 =====
# 固件构建阶段的 PATH 只有交叉工具链（rules.mk 里 export PATH:=$(TARGET_PATH)），
# 既没有宿主 cargo/rustc，也不适合在 CI 里临时拉起 feeds/packages/lang/rust
# （host rust 要现场编译 LLVM，动辄 1~2 小时且占 20GB 磁盘）。
# 因此 WRT-CORE.yml 在编译前用 rustup + zig 交叉编译出 aarch64 musl 静态二进制，
# 放到 src/prebuilt/at-webserver；这里把上游 src/Makefile 的 compile 目标改成
# 「有预编译产物就直接装，否则回退上游 cargo 构建」，install 目标无需改动。
# 上游若调整 compile 规则，下面的结构校验会立刻失败，而不是静默编出旧逻辑。
PREPARE_MT5700_PREBUILT() {
	local MAKE_FILE="$MT5700_DIR/src/Makefile"

	python3 - "$MAKE_FILE" <<'PY'
import io
import re
import sys

path = sys.argv[1]
src = io.open(path, encoding='utf-8').read()

if 'MT5700_PREBUILT_HOOK' in src:
    print('luci-app-mt5700: 预编译注入已存在，跳过')
    sys.exit(0)

if re.search(r'^install:', src, re.M) is None:
    sys.exit('ERROR: src/Makefile 缺少 install 目标，上游结构已变更，需人工复核预编译注入')

new_compile = '''# ==== MT5700_PREBUILT_HOOK（本仓库深度适配，勿手改）====
# 固件构建阶段 PATH 内没有 cargo；CI 已用 rustup + zig 交叉编译出静态后端，
# 放在 src/prebuilt/at-webserver。存在时直接复制到 $(BIN)，否则回退上游 cargo 构建。
compile:
	@if [ -x "$(CURDIR)/prebuilt/at-webserver" ]; then \\
		echo "==> [mt5700] 使用预编译后端: $(CURDIR)/prebuilt/at-webserver"; \\
		mkdir -p "$(dir $(BIN))"; \\
		cp -f "$(CURDIR)/prebuilt/at-webserver" "$(BIN)"; \\
	else \\
		echo "==> [mt5700] cargo build: ARCH=$(ARCH) ARCH_PACKAGES=$(ARCH_PACKAGES) RUST_TARGET=$(RUST_TARGET)"; \\
		cd $(RUST_DIR) && \\
			CARGO_TARGET_DIR="$(CARGO_TARGET_DIR)" \\
			cargo build $(CARGO_BUILD_STD_FLAGS) --release --target $(RUST_TARGET); \\
	fi
	test -x "$(BIN)" || { echo "ERROR: 未产出后端二进制 $(BIN)"; exit 1; }
	@echo "==> [mt5700] 后端二进制就绪: $(BIN)"

'''

patched, n = re.subn(r'(?ms)^compile:.*?(?=^install:)', new_compile, src)
if n != 1:
    sys.exit('ERROR: src/Makefile 的 compile 目标匹配数量为 %d（期望 1），上游结构已变更' % n)

io.open(path, 'w', encoding='utf-8', newline='\n').write(patched)
print('luci-app-mt5700: 已注入预编译后端分支')
PY
}

# ===== 深度适配：让风扇插件在 buildroot 内使用 CI 预编译的 Rust 控制器（2026-10-26）=====
# 与 luci-app-mt5700 同理：固件构建阶段的 PATH 只有交叉工具链（rules.mk 里
# export PATH:=$(TARGET_PATH)），没有 cargo/rustc，也不适合在 CI 里现场编译
# feeds/packages/lang/rust 的 host LLVM。风扇插件 v3.x 的控制器是零依赖 Rust
# crate（.cargo/config.toml 固定 rust-lld，musl 目标自包含静态链接），WRT-CORE.yml
# 在编译前用 rustup 交叉编译出 aarch64 产物放到 src/prebuilt/h5000m-fancontrol；
# 这里把上游 src/Makefile 的 compile 目标改成「有预编译产物就直接装，否则回退
# 上游 cargo 构建」，并把解析期「找不到 cargo 即 $(error)」降级为 $(warning)——
# 否则 buildroot 阶段 Makefile 在解析时就会失败，预编译分支根本走不到。
# 上游若调整 compile 规则，下方的结构校验会立刻失败，而不是静默编出旧逻辑。
PREPARE_FANCONTROL_PREBUILT() {
	local MAKE_FILE="$FANCONTROL_DIR/src/Makefile"

	python3 - "$MAKE_FILE" <<'PY'
import io
import re
import sys

path = sys.argv[1]
src = io.open(path, encoding='utf-8').read()

if 'H5000M_FANCONTROL_PREBUILT_HOOK' in src:
    print('luci-app-h5000m-fancontrol: 预编译注入已存在，跳过')
    sys.exit(0)

if re.search(r'^install:', src, re.M) is None:
    sys.exit('ERROR: src/Makefile 缺少 install 目标，上游结构已变更，需人工复核预编译注入')

# 解析期 cargo 缺失检查降级为 warning：预编译分支下 cargo 不在 PATH 是预期状态；
# 真正回退 cargo 分支时，空的 $(CARGO) 会在命令执行处报错，不会静默通过。
downgraded, n = re.subn(r'^\$\(error (h5000m-fancontrol: cargo not found in PATH)',
                       r'$(warning \1', src, flags=re.M)
if n != 1:
    sys.exit('ERROR: src/Makefile 的 cargo 缺失检查匹配数量为 %d（期望 1），上游结构已变更' % n)

new_compile = '''# ==== H5000M_FANCONTROL_PREBUILT_HOOK（本仓库深度适配，勿手改）====
# buildroot 编译阶段 PATH 内没有 cargo；CI 已用 rustup 交叉编译出静态控制器，
# 放在 prebuilt/h5000m-fancontrol。存在时直接复制到 $(BINARY)，否则回退上游
# cargo 构建；两个分支共用下游的产物存在性与 ELF 架构校验。
compile:
	@if [ -x "$(CURDIR)/prebuilt/h5000m-fancontrol" ]; then \\
		echo "==> [h5000m-fancontrol] 使用预编译控制器: $(CURDIR)/prebuilt/h5000m-fancontrol"; \\
		mkdir -p $(dir $(BINARY)); \\
		cp -f "$(CURDIR)/prebuilt/h5000m-fancontrol" "$(BINARY)"; \\
	else \\
		echo "==> [h5000m-fancontrol] cargo build: ARCH=$(ARCH) RUST_TARGET=$(RUST_TARGET)"; \\
		$(CARGO) build $(CARGO_FLAGS); \\
	fi
	@test -x $(BINARY) || { echo 'ERROR: $(BINARY) missing after build' >&2; exit 1; }
	@if command -v file >/dev/null 2>&1; then \\
		file $(BINARY) | grep -q '$(FILE_MACHINE_$(RUST_TARGET))' || { \\
			echo 'ERROR: $(BINARY) is not a $(RUST_TARGET) ELF binary' >&2; \\
			exit 1; \\
		}; \\
	else \\
		echo 'note: file(1) unavailable, skipping ELF architecture check' >&2; \\
	fi

'''

patched, n = re.subn(r'(?ms)^compile:.*?(?=^clean:)', new_compile, downgraded)
if n != 1:
    sys.exit('ERROR: src/Makefile 的 compile 目标匹配数量为 %d（期望 1），上游结构已变更' % n)

io.open(path, 'w', encoding='utf-8', newline='\n').write(patched)
print('luci-app-h5000m-fancontrol: 已注入预编译控制器分支')
PY
}

PREPARE_MT5700_PREBUILT
PREPARE_FANCONTROL_PREBUILT

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
