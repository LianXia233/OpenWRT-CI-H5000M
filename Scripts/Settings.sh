#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/mediatek/filogic/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config

# ===== 主题配套包 =====
# 默认主题由 WRT_THEME 决定（当前 vantage）；luci-theme-bootstrap 已在脚本开头被
# 替换成 luci-theme-$WRT_THEME，故未安装的主题不会抢占默认样式。
# 各主题的配套包名并不统一（aurora → luci-app-aurora-config、vantage →
# luci-app-vantage 仪表盘、argon → luci-app-argon-config），无脑拼
# luci-app-$WRT_THEME-config 会写出不存在的符号，defconfig 阶段会被静默丢弃
# （QModem 仓库有 check_defconfig.py 硬断言，这里保持写法一致以免迁移时踩坑）。
THEME_PKG=""
case "$WRT_THEME" in
	aurora)  THEME_PKG="luci-app-aurora-config" ;;
	vantage) THEME_PKG="luci-app-vantage" ;;
	argon)   THEME_PKG="luci-app-argon-config" ;;
esac
if [ -n "$THEME_PKG" ]; then
	echo "CONFIG_PACKAGE_$THEME_PKG=y" >> ./.config
fi

# Aurora 保留为可选主题（编入固件但不再默认），可在「系统 → 语言和界面」切回
if [ "$WRT_THEME" != "aurora" ]; then
	echo "CONFIG_PACKAGE_luci-theme-aurora=y" >> ./.config
	echo "CONFIG_PACKAGE_luci-app-aurora-config=y" >> ./.config
fi

# ===== 默认主题种子（首启动 uci-defaults）=====
# 集合依赖换成 luci-theme-$WRT_THEME 只能保证「该主题被安装」，无法保证
# /etc/config/luci 的 mediaurlbase 指向它：该文件是 conffile，sysupgrade 保留旧
# 配置时仍写着上一代默认（/luci-static/aurora），而主题包自带的 30_luci-theme-*
# 脚本只在 luci.themes.<Name> 首次注册时才写 mediaurlbase，升级路径不会切换。
# 这里生成一个排在 30_* 之后执行的种子脚本：
#   - 主题目录不存在（未编入）则不动配置，避免留下坏路径；
#   - 用 luci.main.theme_seeded 记录已种子过的默认主题，同一代主题只种一次，
#     用户此后在 LuCI 里改的主题不会被每次升级重置；日后更换默认主题时该值
#     不等，种子脚本会重新生效。
THEME_SEED_DIR="./files/etc/uci-defaults"
mkdir -p "$THEME_SEED_DIR"
THEME_NAME="$(printf '%s' "${WRT_THEME:0:1}" | tr '[:lower:]' '[:upper:]')${WRT_THEME:1}"
cat > "$THEME_SEED_DIR/40-luci-default-theme" <<EOF
#!/bin/sh
# 出厂默认主题：构建时由 Scripts/Settings.sh 依据 WRT_THEME 生成，勿手改
THEME='$WRT_THEME'
THEME_NAME='$THEME_NAME'

[ -n "\$THEME" ] || exit 0
[ -d "/www/luci-static/\$THEME" ] || exit 0
[ "\$(uci -q get luci.main.theme_seeded)" = "\$THEME" ] && exit 0

uci -q set "luci.themes.\$THEME_NAME=/luci-static/\$THEME"
uci -q set luci.main.mediaurlbase="/luci-static/\$THEME"
uci -q set luci.main.theme_seeded="\$THEME"
uci -q commit luci
exit 0
EOF
chmod +x "$THEME_SEED_DIR/40-luci-default-theme"
echo "default theme seeded: $WRT_THEME"

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi
