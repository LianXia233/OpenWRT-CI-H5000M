#!/bin/bash
# SPDX-License-Identifier: MIT
# 全机型通用：把 luci-app-online-upgrade 源码放进 package/
#
# 为什么独立成脚本而不写进 Scripts/Packages.sh：Packages.sh 基于
# UPDATE_PACKAGE 的「feeds 内同名目录删除 + clone + 可选下钻/改名」范式，本包
# 是「包即仓库根」（Makefile / root/ / rust/ 都在仓库根），且不来自 feeds，
# 也不需要清理同名 feeds 目录，用独立脚本表达更直接。导入与预编译两个阶段
# 职责分离：本脚本只负责源码就位与缺陷修正，Rust 二进制由 WRT-CORE 的
# Cross Compile Online Upgrade Backend 步骤预编译后放到
# package/luci-app-online-upgrade/root/usr/bin/online-upgrade。
#
# 用法（在 OpenWrt 源码树的 package/ 目录下执行）：
#   $GITHUB_WORKSPACE/Scripts/Packages-OnlineUpgrade.sh
#
# 环境变量（可选）：
#   ONLINE_UPGRADE_REPO     上游仓库，默认 LianXia233/luci-app-online-upgrade
#   ONLINE_UPGRADE_BRANCH   上游分支，默认 main

set -euo pipefail

PKG_NAME=luci-app-online-upgrade
PKG_REPO="${ONLINE_UPGRADE_REPO:-LianXia233/luci-app-online-upgrade}"
PKG_BRANCH="${ONLINE_UPGRADE_BRANCH:-main}"

# clone 到临时目录再搬移，避免与目标包目录同名互相覆盖
REPO_DIR=".${PKG_NAME}-upstream"

echo "==> 拉取 ${PKG_NAME}（${PKG_REPO}@${PKG_BRANCH}）"

# 幂等：重复执行先清干净，避免旧版本文件残留造成包内容混杂
rm -rf "./${PKG_NAME}" "./${REPO_DIR}"

# 托管 runner 在境外，直连为主；本机（国内网络）直连不稳时走加速镜像。
# 镜像只用于拉取，不涉及任何凭据。
if ! git clone --depth=1 --single-branch --branch "${PKG_BRANCH}" \
	"https://github.com/${PKG_REPO}.git" "./${REPO_DIR}" 2>/dev/null; then
	echo "::warning::直连 clone 失败，改用加速镜像重试"
	git clone --depth=1 --single-branch --branch "${PKG_BRANCH}" \
		"https://gh.acg2.mom/https://github.com/${PKG_REPO}.git" "./${REPO_DIR}"
fi

# 发布构建用不到的目录：.git 体积大，.github 是上游 CI
rm -rf "./${REPO_DIR}/.git" "./${REPO_DIR}/.github"

[ -f "./${REPO_DIR}/Makefile" ] || {
	echo "::error::${REPO_DIR}/Makefile 不存在：上游仓库布局可能已变更"
	echo "目录内容：$(ls -A "./${REPO_DIR}" | tr '\n' ' ')"
	exit 1
}

mv "./${REPO_DIR}" "./${PKG_NAME}"

# ===== 行尾归一化：CRLF → LF =====
# 只处理文本类文件。上游若在 Windows 下提交过 uci-defaults / rpcd 脚本，
# 行尾 \r 会让 shebang 变成 "#!/bin/sh\r"，设备上表现为脚本解释器不存在；
# Makefile 的 include 行带 \r 会直接报 luci.mk 找不到。
# 二进制（截图等）不参与转换：sed 对含 0x0d 的二进制会破坏内容。
mapfile -t PKG_TEXT_FILES < <(
	find "./${PKG_NAME}" -type f \
		\( -name '*.sh' -o -name '*.uc' -o -name '*.js' -o -name '*.css' \
		-o -name '*.json' -o -name '*.ut' -o -name '*.md' -o -name '*.txt' \
		-o -name '*.toml' -o -name '*.rs' -o -name '*.lock' -o -name 'Makefile' \)
)
if [ "${#PKG_TEXT_FILES[@]}" -gt 0 ]; then
	sed -i 's/\r$//' "${PKG_TEXT_FILES[@]}"
fi

# 复核：按字节比较转换前后长度，确认不再有 CR（不用 grep -qU $'\r'：
# 该写法在 Git Bash / MSYS 下对 CR 的判定不可靠）
CR_LEFT=()
for F in "${PKG_TEXT_FILES[@]}"; do
	ORIG_LEN=$(wc -c < "$F")
	STRIPPED_LEN=$(tr -d '\r' < "$F" | wc -c)
	if [ "$ORIG_LEN" != "$STRIPPED_LEN" ]; then
		CR_LEFT+=("$F")
	fi
done
if [ "${#CR_LEFT[@]}" -ne 0 ]; then
	echo "::error::${PKG_NAME} 仍存在含 CR 的文件，行尾归一化未完成"
	for F in "${CR_LEFT[@]}"; do
		echo "  含 CR: $F"
	done
	exit 1
fi
echo "==> 行尾复核通过：${#PKG_TEXT_FILES[@]} 个文本文件均为 LF"

# ===== 结构断言：上游改动导致接入前提失效时立即红掉 =====
# 1) 必需 feeds/luci/luci.mk：包是 LuCI 应用，缺它 make 直接失败
grep -q 'feeds/luci/luci.mk' "./${PKG_NAME}/Makefile" || {
	echo "::error::${PKG_NAME}/Makefile 未引用 feeds/luci/luci.mk：上游打包方式可能已变更"
	grep -n 'luci.mk' "./${PKG_NAME}/Makefile" || echo "（Makefile 中无 luci.mk 引用）"
	exit 1
}

# 2) 安装段必须从 ./root/usr/bin/online-upgrade 取二进制：本仓库不在
#    buildroot 内编译 Rust（上游 Build/Prepare 与 Build/Compile 均为空），
#    而是 CI 预编译后放到该路径。上游若改成 buildroot 内编译，这里会先失败。
grep -q './root/usr/bin/online-upgrade' "./${PKG_NAME}/Makefile" || {
	echo "::error::${PKG_NAME}/Makefile 不再安装 ./root/usr/bin/online-upgrade："
	echo "  预编译产物落点与本仓库接入方式需要同步调整"
	exit 1
}
# 三处路径一致性：Makefile 安装目标 $(1)/usr/bin/online-upgrade = 设备上
# 守卫判定的 /usr/bin/online-upgrade = CI 预编译产物落点 root/usr/bin/online-upgrade。
# 任一不一致都会导致「包内有二进制但守卫判不到」或「守卫判到却装不上」。
grep -qF '$(1)/usr/bin/online-upgrade' "./${PKG_NAME}/Makefile" || {
	echo "::error::${PKG_NAME}/Makefile 的安装目标不是 \$(1)/usr/bin/online-upgrade：三处路径不一致"
	exit 1
}

# 3) Rust 工程目录：预编译步骤按 <包>/rust 取源码
[ -f "./${PKG_NAME}/rust/Cargo.toml" ] || {
	echo "::error::${PKG_NAME}/rust/Cargo.toml 不存在：上游 Rust 后端目录可能已改名"
	exit 1
}
[ -f "./${PKG_NAME}/rust/Cargo.lock" ] || {
	echo "::error::${PKG_NAME}/rust/Cargo.lock 不存在：无法 --locked 复现依赖树"
	exit 1
}

# 4) 默认 UCI 配置文件：预设配置的键名以它为基线
[ -f "./${PKG_NAME}/root/etc/config/online-upgrade" ] || {
	echo "::error::${PKG_NAME}/root/etc/config/online-upgrade 不存在：上游默认配置路径可能已变更"
	exit 1
}

# 5) release profile 收敛（影响产物体积与可复现性）：
#    opt-level="z" / lto=true / codegen-units=1 / panic="abort" / strip=true。
#    strip=true 已由 Cargo 在链接后执行，等价于显式 strip；上游若改动这些键，
#    产物会变大或与既有固件的调试符号策略不一致，故在此硬性断言。
for KV in 'opt-level = "z"' 'lto = true' 'panic = "abort"' 'strip = true' 'codegen-units = 1'; do
	grep -qF "$KV" "./${PKG_NAME}/rust/Cargo.toml" || {
		echo "::error::${PKG_NAME}/rust/Cargo.toml 缺少 release 收敛项 [profile.release] ${KV}"
		exit 1
	}
done

# ===== 预编译产物落点：上游不提交二进制，目录需由本仓库创建 =====
# Makefile 的 install 段用 $(INSTALL_BIN) ./root/usr/bin/online-upgrade，
# 该文件由 Cross Compile Online Upgrade Backend 步骤写入；这里先建目录，
# 保证后续 cp 与 buildroot 的 install 路径都成立。
mkdir -p "./${PKG_NAME}/root/usr/bin"

# ===== 上游缺陷修正：90-online-upgrade-auto 的存在性守卫（按内容判定、幂等）=====
# 背景：该脚本本意是「仅在插件确实缺失时尝试重装」。v1 时期二进制叫
# /usr/bin/online-upgrade.sh，守卫因此判 .sh；v2 只安装 /usr/bin/online-upgrade，
# 且同包的 99-online-upgrade 还会 rm -f 那个 .sh。若守卫仍判 .sh，每次刷机首启
# 都会误判「插件丢失」，转而从外部仓库下载 .apk 并 apk add --allow-untrusted，
# 可能覆盖本仓库自己构建的二进制。
#
# 上游已在 98a966a（2026-11-08）修复该缺陷：守卫改为
#   [ -x /usr/bin/online-upgrade ] && exit 0
#   if [ ! -x /usr/bin/online-upgrade ]; then ...
# 因此这里不再无条件 sed（那会误伤已修复的上游），只在内容里确实残留 v1 路径时
# 才改写，并始终做构建期断言：最终文件必须引用 /usr/bin/online-upgrade，且不得
# 残留 online-upgrade.sh 引用。上游未来若再次回退，断言会立即红掉。
AUTO_UCI="./${PKG_NAME}/root/etc/uci-defaults/90-online-upgrade-auto"
if [ -f "$AUTO_UCI" ]; then
	if grep -qF 'online-upgrade.sh' "$AUTO_UCI"; then
		echo "==> ${AUTO_UCI} 仍引用 v1 路径 online-upgrade.sh，按内容改写为 v2 二进制"
		# 只把「v1 二进制路径」改成 v2 路径；注释里的历史说明不受影响
		sed -i 's#/usr/bin/online-upgrade\.sh#/usr/bin/online-upgrade#g' "$AUTO_UCI"
	else
		echo "==> ${AUTO_UCI} 已是 v2 路径（上游已修复），不修改"
	fi
	# 构建期断言（无论是否改写都要过）：守卫必须判定 v2 二进制，且不得残留 v1 引用
	grep -qF '/usr/bin/online-upgrade' "$AUTO_UCI" || {
		echo "::error::${AUTO_UCI} 未引用 /usr/bin/online-upgrade：守卫路径与本包安装路径不一致"
		exit 1
	}
	if grep -vE '^[[:space:]]*#' "$AUTO_UCI" | grep -qF 'online-upgrade.sh'; then
		echo "::error::${AUTO_UCI} 的代码行仍残留 v1 路径 online-upgrade.sh，守卫修正未生效"
		exit 1
	fi
	echo "==> 守卫路径核对通过：$(grep -nF '/usr/bin/online-upgrade' "$AUTO_UCI" | head -3 | tr '\n' ' ')"
else
	echo "::warning::${AUTO_UCI} 缺失：上游目录结构可能已调整"
fi

# 可执行位补齐：git clone 一般保留 mode，但上游经 Windows 提交或 archive
# 分发时 x 位可能丢失，导致 uci-defaults 在设备上不执行。
for FILE in root/etc/uci-defaults/99-online-upgrade root/etc/uci-defaults/90-online-upgrade-auto; do
	if [ -f "./${PKG_NAME}/${FILE}" ]; then
		chmod +x "./${PKG_NAME}/${FILE}"
	else
		echo "::warning::${PKG_NAME}/${FILE} 缺失：上游目录结构可能已调整"
	fi
done

# ===== 版本记录：供 Release Notes 引用 =====
PKG_VER=$(sed -n 's/^PKG_VERSION:=//p' "./${PKG_NAME}/Makefile" | head -1)
BACKEND_VER=$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "./${PKG_NAME}/rust/Cargo.toml" | head -1)
echo "==> ${PKG_NAME} 就位：plugin ${PKG_VER} / backend ${BACKEND_VER}"
[ -n "${GITHUB_ENV:-}" ] && echo "ONLINE_UPGRADE_VERSION=plugin ${PKG_VER} / backend ${BACKEND_VER}" >> "$GITHUB_ENV"

echo "==> 目录内容：$(cd "./${PKG_NAME}" && ls -A | tr '\n' ' ')"
