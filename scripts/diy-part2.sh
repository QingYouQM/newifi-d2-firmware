#!/bin/bash
# diy-part2.sh —— .config 生成之后、正式编译之前执行
# 作用: 注入 files/ 目录、改发行版标识、按需追加配置

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> [diy-part2] 注入 files/ 覆盖层"
if [ -d "$ROOT/files" ]; then
    cp -rf "$ROOT/files/." package/base-files/files/
    chmod +x package/base-files/files/etc/uci-defaults/* 2>/dev/null || true
    chmod +x package/base-files/files/usr/bin/* 2>/dev/null || true
    echo "    files/ 已合并进 rootfs"
fi

echo "==> [diy-part2] 修改发行版标识"
STAMP="$(date +%Y%m%d)"
REL="package/base-files/files/etc/openwrt_release"
if [ -f "$REL" ]; then
    sed -i "s|^DISTRIB_DESCRIPTION=.*|DISTRIB_DESCRIPTION='ImmortalWrt D2 (build ${STAMP})'|" "$REL"
    echo "    $(grep DISTRIB_DESCRIPTION "$REL")"
fi

echo "==> [diy-part2] 追加自定义选项"
cat >> .config <<'EXTRA_CFG'

# ---- 追加: 让固件默认带一个能用的中文界面 ----
CONFIG_LUCI_LANG_zh_Hans=y
# ---- 追加: 默认打开 UPnP(加速器 App 依赖) ----
CONFIG_PACKAGE_luci-app-upnp=y
EXTRA_CFG

echo "==> [diy-part2] 完成"
