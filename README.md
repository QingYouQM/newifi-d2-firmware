# Newifi D2 定制固件工程（主路由版）

给 **新路由3 / Newifi D2（d-team_newifi-d2）** 定做的 ImmortalWrt 固件。
定位：**这台机器当主路由拨号，WiFi 也由它发，并且能直接跑主机游戏加速器。**

基线 `ImmortalWrt openwrt-21.02`（内核 5.4 / iptables / fw3），原因是加速器生态还压在
iptables 上，21.02 是兼容性最稳的一档。

---

## 一、先说加速器：三种的实测结果

这一节的所有结论都是我逐个下载二进制验证过的，不是抄教程。

### 雷神：**可以装，但有坑** ⚠️

踩坑记录值得写下来，因为论坛上大量「装不上」的帖子都是同一个原因。

雷神的安装脚本靠 `uname -m` 拼二进制文件名，服务器上的实际文件是：

| 文件 | 结果 |
|---|---|
| `acc-gw.router.mipsel` | **200，9,084,928 字节** ← MT7621 要的就是这个 |
| `acc-gw.router.arm64` | 200，7,614,504 字节 |
| `acc-gw.router.arm` | 200，7,101,084 字节 |
| `acc-gw.router.mips` | **404** |

我把 `acc-gw.router.mipsel` 下下来验了 ELF 头：`32 位 / 小端 LSB / e_machine=0x8 (MIPS)`，
**和 MT7621（mipsel_24kc）完全匹配**。

问题出在 MIPS 内核里 `uname -m` 返回的是 `mips` 而不是 `mipsel`。
**旧版脚本**（`router_plugin` 目录）没有做映射，直接去取 `acc-gw.linux.mips` → 404 → 安装失败。
**新版脚本**（`router_plugin_new` 目录）在 `preinstall_check` 里补了这段：

```sh
elif [ ${arch} == "mips" ]; then
    echo "match mips -> mipsel"
    arch="mipsel"
fi
```

所以**用新版脚本就能装上**。这也是 CatWrt 敢写「新路由3 支持雷神」的原因。

### 奇游：可以 ✅

`QYPLUG_SYS_MIPSX2_1.2.1.tar.gz` 实测 200 / 5,284,680 字节，脚本按 ELF 头识别 32 位小端 MIPS32，
而且同时兼容 iptables 和 nftables，不挑固件。

### 网易 UU：可以 ✅

官方 install.sh 接受 `$(uname -m)`，文档明确支持 mips 小端，依赖只有 `kmod-tun`。

---

## 二、为什么还要自己编，不直接刷现成的

现成固件能刷，但装加速器会撞三个坑：

1. **缺依赖**。奇游要 `tc-full ip-full kmod-tun curl`，UU 要 `kmod-tun`，纯净固件基本没有，
   而 21.02 已 EOL、`opkg update` 大概率连不上源，卡死在这儿。
   → 本工程把这些**全部编进固件**，不依赖联网装包。
2. **UPnP 没开**。手机 App 靠 UPnP 发现路由插件，关着就永远「找不到设备」。
   → 默认开启 `miniupnpd`。
3. **flow offloading 冲突**。MT7621 的硬件 NAT 会绕过 iptables，加速规则被跳过，
   表现为「开了加速但延迟没降，甚至断网」。
   → 首次启动显式关闭 `flow_offloading` / `flow_offloading_hw`。

---

## 三、固件里装了什么

| 类别 | 内容 |
|---|---|
| 系统 | ImmortalWrt 21.02、LuCI 中文、默认时区/主机名/NTP |
| 加速器环境 | `kmod-tun` `tc-full` `ip-full` `ipset` `kmod-ipt-tproxy` `kmod-ipt-nat` `kmod-ipt-ipset` `kmod-netem` `curl` `libpcap` |
| UPnP | `miniupnpd` + `luci-app-upnp`，默认已启用 |
| 网络 | `kmod-tcp-bbr`（BBR 拥塞控制），flow offloading 已关闭 |
| 存储 | `kmod-usb-storage` `kmod-fs-ext4/vfat/exfat` `block-mount`（USB3.0 挂盘，也是 extroot 的前提） |
| 运维 | `luci-app-ttyd`（网页终端）`openssh-sftp-server` `htop` `nano` |
| 自带脚本 | `/usr/bin/leigod-d2` —— 雷神安装助手（见第七节） |

固件里**不含**加速器二进制本身（闭源、按账号绑定），那部分刷完再装，所以重刷固件不影响账号和时长。

---

## 四、空间账：这是本工程最需要你注意的地方

D2 只有 **32MB SPI Flash**，firmware 分区约 31MB。固件本身约 **10~11MB**，
留给 overlay（可写分区）的只有 **20MB 左右**。

而雷神装完要占：

```
/usr/sbin/leigod/acc-gw.router.mipsel   9 MB   主程序
/usr/sbin/leigod/acc_upgrade_monitor    9 MB   官方脚本会 cp 一份副本
/usr/sbin/leigod/ipdatacloud_country.xdb  1~3 MB
```

**18MB 以上**。也就是说装完基本就满了，再想装别的插件没地方。

工程里给了 `/usr/bin/leigod-d2` 这个助手，安装后会自动把副本换成软链，**回收 9MB**。
即便如此，建议按优先级选一条路：

- **A（省事）**：只装雷神，不装别的。装完剩 8~9MB，够用但不宽裕。
- **B（推荐）**：extroot —— 插个 U 盘，把 overlay 整个搬到 U 盘上，从此不受 32MB 限制。
  需要 U 盘（≥2GB，建议 A 级颗粒）+ `block-mount`（已内置）。
- **C**：改用奇游（5MB 量级），空间压力小很多。

---

## 五、编译：全程在 GitHub 云端跑

> 本机是 Windows，WSL 被安全策略禁用、也没有 Docker，本地编译这条路走不通。
> 云端编译完直接下 bin，反而更省事。

**1. 建仓库（必须 Public）**

私有仓库每月只有 2000 分钟免费额度，一次编译就吃掉 150 分钟以上，公开仓库不计量。

```bash
cd D:/CodingTrash/NewifiD2
git init
git add .
git commit -m "newifi d2 custom firmware"
git branch -M main
git remote add origin https://github.com/<你的用户名>/newifi-d2-firmware.git
git push -u origin main
```

**2. 触发**

仓库页面 → `Actions` → `Build Newifi D2 Firmware` → `Run workflow`
- `branch`：`openwrt-21.02`（默认）
- `config_file`：`configs/d2.config`

**3. 等**

首次 2~3 小时（要拉全量源码包），之后有 `dl` 缓存，1.5 小时左右。超时上限 350 分钟。

**4. 下载**

构建完成 → 本次 run 页面底部 `Artifacts` → `newifi-d2-openwrt-21.02.zip`。
要的是 **`newifi-d2-YYYYMMDD-openwrt-21.02-sysupgrade.bin`**（约 10MB）。
`initramfs` 那个是救砖用的，正常不用。

---

## 六、刷进去

### 0. 先有 Breed（原厂固件才需要）

```bash
# 浏览器打开（假设原厂 IP 是 192.168.99.1）
http://192.168.99.1/newifi/ifiwen_hss.html   # 显示 success 表示 SSH 已开

# 把 newifi-d2-jail-break.ko 传到 /tmp 后
cd /tmp && insmod newifi-d2-jail-break.ko
# SSH 会卡死，正常现象，别断电，等它自己重启
```

断电，**按住 Reset 或 USB 键再上电**，电源灯闪 → 浏览器进 `http://192.168.1.1`。

### 1. Breed 里刷固件

1. 进 Breed 后先进「固件备份」，把 **EEPROM** 和「编程器固件」各存一份
   （**别偷懒，EEPROM 丢了无线就废了**）
2. 「固件更新」→ 勾「固件」→ 选 `...-sysupgrade.bin` → 上传
3. 等 2~3 分钟自动重启

> 必须用 `sysupgrade.bin`，别刷 `factory.bin`，Breed 下刷 factory 会失败。

---

## 七、主路由怎么配

刷完开机：`192.168.1.1`，用户 `root`，密码空（首次登录会让你设）。中文界面、时区、NTP 都已就绪。

**出厂已配好的：**
- 双频 WiFi 已开启，**2.4G 与 5G 合并为一个 SSID：`NewifiD2`**，密码 `12345678`
- 主机名 `NewifiD2`，UPnP 已启用，flow offloading 已关闭

**你要做的：**

1. **立刻改 WiFi 密码** — 网络 → 无线 → 编辑 → 无线安全
2. **WAN 拨号** — 网络 → 接口 → `WAN` → 修改 → 协议选 `PPPoE` → 填宽带账号密码 → 保存并应用
3. （可选）**关 IPv6** — 网络 → 接口 → `WAN6` → 删除。游戏加速在纯 IPv4 下更稳，
   这也是加速器官方管理器里「手机优化」做的事

**拓扑**：光猫桥接 → D2 的 WAN 口 → D2 拨号 → LAN 口/WiFi 接设备。
光猫要改成桥接模式，否则是双重 NAT，联机游戏会遇到 NAT 类型受限。

### 关于双频合一

`NewifiD2` 这一个 SSID 会同时从 2.4G 和 5G 两个射频广播出去，密码与加密方式完全一致，
终端搜到哪个就连哪个。

- **好处**：全屋只记一个 WiFi；从客厅走到卧室换频段时不需要手动切换，也不会重新走一遍 DHCP
- **局限**：这**不是真正的频谱引导（band steering）**。D2 是 MT7603（2.4G）+ MT7612（5G）
  两颗独立芯片，开源 mt76 驱动里没有跨芯片的引导逻辑，做不到"信号变弱就把你推到 5G"。
  手机和笔记本通常会自动优先 5G，但部分安卓机和智能家居会一直黏在 2.4G 上
- **对加速的影响**：2.4G 的延迟抖动明显大于 5G，会吃掉加速器的收益。
  要玩游戏的主机/PC 建议直接接网线；手机、平板确认自己连的是 5G

想拆回两个独立 SSID：网络 → 无线 → 编辑任一 AP → 把 SSID 改成 `NewifiD2-5G`，
两个频段就变成互不相干的两套网络（代价是换房间要手动切）。

> 首启脚本只在**新刷机或恢复出厂**后执行一次。以后重刷固件如果勾了"保留配置"，
> 这里的 SSID 不会重新生成，需要按上面的方法手动改。

### 能不能关掉 2.4G？能。能不能"交给 MT7621"？不能。

MT7621AT 是纯 SoC（双核 MIPS + 交换机 + PCIe 控制器），**没有射频和基带**。
2.4G 只由外挂的 MT7603EN 提供，5G 由 MT7612EN 提供，两颗芯片各自挂在 PCIe 上。
SoC 只负责跑协议栈、转发报文，调制解调它做不了。

所以关掉 MT7603 的唯一结果是 **2.4G 彻底消失**，不会把负载转移给 CPU，5G 的速率和覆盖也不会因此变好。

**编译时关**：把 `files/etc/uci-defaults/99-d2-defaults` 里的 `ENABLE_2G='1'` 改成 `'0'`。

**已经刷好机想在运行时自由开关**（不用重编译、不用重启路由器）：

```sh
wifi-band              # 看两个频段当前状态
wifi-band 2.4 off      # 关 2.4G
wifi-band 5 off        # 关 5G
wifi-band all on       # 两个都打开
```

生效约 5~10 秒，期间无线会短暂中断。**两个都关掉后就只能靠网线进后台了。**

> ⚠️ **别手写 `radio0` / `radio1`**。这台机器的编号和直觉是反的：
> `pcie0` 挂的是 MT7612EN（5G）→ `radio0`，`pcie1` 挂的是 MT7603EN（2.4G）→ `radio1`。
> DTS 里可以直接看出来（`pcie0` 带 `freq-limit = <5000000 6000000>` 且 eeprom 在 0x8000）。
> `wifi-band` 是按 `band` 字段查找的，不受编号影响。

图形界面里也能开关：网络 → 无线 → 对应频段那一行的「启用」复选框。

**收益与代价**：收益很小（少一路 beacon、少一个中断源、省几十毫瓦），
代价是失去 2.4G 的穿墙能力和所有只支持 2.4G 的智能家居。D2 的 5G 只有 2×2、
本身穿墙就一般，单靠 5G 覆盖全屋基本不现实。

如果 2.4G 是"卡、掉线、速度上不去"，别急着关——先换 12V/3A 电源
（原装适配器纹波大，是无线间歇断流的常见元凶），再看 USB 3.0 干扰：
USB 3.0 的辐射谐波正好落在 2.4G 频段，插着硬盘时 2.4G 掉速在带 USB3.0 的路由器上很常见，
把硬盘挪远、换带屏蔽的线通常能缓解。

如果 2.4G 是"卡、掉线、速度上不去"，别急着关——先换 12V/3A 电源
（原装适配器纹波大，是无线间歇断流的常见元凶），再看 USB 3.0 干扰：
USB 3.0 的辐射谐波正好落在 2.4G 频段，插着硬盘时 2.4G 掉速在带 USB3.0 的路由器上很常见，
把硬盘挪远、换带屏蔽的线通常能缓解。

---

## 八、装雷神加速器

```bash
# SSH 进路由器（或用 LuCI 里的终端）
leigod-d2 space      # 先看空间够不够
leigod-d2 install    # 调用官方新版脚本安装，装完自动回收 9MB
leigod-d2 status     # 检查结果
```

装完：手机连 `NewifiD2`（确认连的是 5G）→ 打开雷神加速器 App → 硬件加速 → 添加设备 → 看到路由器插件即可绑定。

**如果 install 失败：**
- `overlay 空间不足` → 先做 extroot，或者改用奇游
- 网络问题 → 固件里 curl 已内置，确认路由器本身能上网

> 手动安装的等价命令（不用助手脚本时）：
> ```bash
> cd /tmp && sh -c "$(curl -fsSL http://119.3.40.126/router_plugin_new/plugin_install.sh)"
> ```
> 注意必须是 `router_plugin_new` 这个新路径，旧的 `router_plugin` 里没有 mipsel 文件。

### 备选：奇游

```bash
curl -s sd.qiyou.cn | sh
```
体积只有 5MB 量级，空间紧张时用它更从容。两个加速器不要同时开，会抢流量规则。

---

## 九、常见问题

**编译失败？**
看 `build-log-failed` 这个 artifact，把最后 50 行发出来。21.02 是老代码，在 Ubuntu 22.04 上
偶发 host 工具报错，多数是缺 `python3-distutils`、`libelf-dev` 之类，workflow 里已经装了。

**刷完进不去后台？**
确认电脑是 DHCP 自动获取；确认刷的是 sysupgrade 而不是 factory。Breed 里能重刷，砖不了。

**加速开了没效果？**
三处检查：① 防火墙 → 基本设置 → 软件/硬件流量卸载必须**都关**（固件已默认关）；
② UPnP 必须是启用状态；③ 主机要接在这台路由下面，不能跨网段。

**无线断流？**
先换电源。原装 12V/2A 纹波大是通病，换 12V/3A 品牌电源能解决大半。再加个散热片。

**想上 24.10？**
Run workflow 时把 `branch` 改成 `openwrt-24.10`。但 24.10 是 nftables，
雷神要用新版脚本（它自带 `detect_and_set_firewall_backend` 做兼容），UU 需要额外补 `iptables-nft`。
追求省心就留在 21.02。

---

## 十、目录结构

```
.
├── .github/workflows/build.yml          # 云端编译流水线
├── configs/d2.config                    # 固件配置（seed config）
├── scripts/diy-part1.sh                 # feeds 精简
├── scripts/diy-part2.sh                 # 注入 files/、改发行版标识
└── files/                               # 直接覆盖到 rootfs
    ├── etc/config/luci                  # 默认中文
    ├── etc/uci-defaults/99-d2-defaults  # 首启配置：双频合一 WiFi/UPnP/关流卸载
    ├── usr/bin/wifi-band                # 按频段开关无线（不受 radio 编号影响）
    └── usr/bin/leigod-d2                # 雷神安装助手（空间回收）
```
