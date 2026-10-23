#!/bin/bash
# diy-part1.sh —— feeds update 之后、feeds install 之前执行
# 作用: 精简 feeds 体积，缩短云端编译时间

set -e

echo "==> [diy-part1] 精简 luci 应用列表"

# 这些应用本项目用不到，删掉可以少解压几千个文件。
# 如果以后想在固件里集成（比如 OpenClash），把对应名字从这里删掉即可。
UNUSED_APPS="
samba4
nfs
ddns
sqm
https-dns-proxy
transmission
qbittorrent
aria2
openclash
passwall
ssr-plus
vssr
docker
dockerman
unblockneteasemusic
mwan3
"

for app in $UNUSED_APPS; do
    if [ -d "feeds/luci/applications/luci-app-${app}" ]; then
        rm -rf "feeds/luci/applications/luci-app-${app}"
        echo "    removed luci-app-${app}"
    fi
done

echo "==> [diy-part1] 完成"
