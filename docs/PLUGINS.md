# 固件里这几个功能怎么用

刷完先确认 NSS 在干活，再看插件。

## 开机默认地址：192.168.10.254

镜像里带了一个 uci-defaults 脚本（仓库路径 `overlay/etc/uci-defaults/99-custom-lan-ip`，
编译时被复制进 base-files），**第一次启动**时把 LAN 改成：

- 地址：`192.168.10.254/24`
- DHCP 池：`192.168.10.100 ~ 192.168.10.249`，租期 12h

所以刷完直接访问 **`http://192.168.10.254`**，不是 192.168.1.1。这个脚本只跑一次，之后随便改。

- 想换别的地址：改 `overlay/etc/uci-defaults/99-custom-lan-ip` 里的两个 `uci set`，重编；
  已经刷过的机器也可以直接 `uci set network.lan.ipaddr=...` + `uci commit network` 后重启。
- 当 AP / 旁路由用（上游已经有一台 DHCP）：进 LuCI → 网络 → 接口 → LAN，把「DHCP 服务器」关掉，
  否则会和上游 DHCP 打架、客户端随机拿到错误的网关。
- 地址段冲突：如果你上游网段不是 192.168.10.0/24，务必先改这里再刷，不然你会连不上它。

## 0. NSS 是否生效

```sh
# 模块是否加载
lsmod | grep -E 'qca_nss|ecm'

# 启动日志里能看到 NSS 固件版本（11.4 之类）
dmesg | grep -i nss | head

# debugfs 里有 NSS 目录（需 mount -t debugfs none /sys/kernel/debug）
ls /sys/kernel/debug/qca-nss-drv/ 2>/dev/null
```

实测方法：`iperf3` 打满千兆时看 `top`，`ksoftirqd`/`sirq` 的 CPU 占用应该很低；如果直接飙到 60%+，说明流量没走 NSS（常见原因：开了不兼容的 qdisc、走了 NSS 不支持的封装）。

---

## 1. miniupnpd（UPnP IGD）

**位置**：LuCI → 服务 → UPnP

- 勾选「启用」，内网接口选 `br-lan`（或你的 LAN 桥）。
- 下行/上行速率按实际填，影响 IGD 上报值，不影响实际转发。
- BT / 游戏机 / 监控需要它；开了 NSS 硬件加速也能正常工作。
- 23.05 之后是 nftables 版（`miniupnpd-nftables`），配置文件仍是 `/etc/config/upnpd`。

---

## 2. iStore 应用商店

**位置**：LuCI → 首页 → iStore

- 首次打开要联网拉取应用列表（走 `curl`，需要能出网）。
- 装插件走它自己的任务队列（`taskd`），点安装后等几秒刷新页面。
- 装的东西来自 iStore 源，和你手动 opkg/apk 装的包走同一套包管理，可能互相覆盖版本，注意看提示。
- 打不开页面的第一嫌疑：镜像里缺 `luci-compat` / `luci-lua-runtime`（本项目已在 base.config 里带上，可用 `opkg list-installed | grep luci-compat` 复核）。

---

## 3. 微信推送（tty228 版 v3.6.x）

**位置**：LuCI → 服务 → 微信推送

**填什么**：

| 通道 | 需要填 |
| --- | --- |
| Server酱 | `SCT...` 开头的 SendKey |
| PushPlus | token |
| 企业微信机器人 | webhook 地址里的 key |
| Telegram | bot token + chat id |

**已知限制**：页面上的「流量统计」依赖 `wrtbwmon`，作者自己说明它**可能和 Flow Offloading / NSS 卸载冲突，导致统计不到流量**，所以本项目默认没开这个子选项。上下线、温度、磁盘、CPU 这些推送不受影响。

---

## 4. DDNSTO 远程控制

**位置**：LuCI → 服务 → DDNSTO

- 去 ddnsto.com 微信扫码登录，拿到令牌（token），粘进页面保存即启动。
- 之后用 `https://你的前缀.ddnsto.com` 从外网访问路由器，不需要公网 IP、不用端口映射。
- 二进制是闭源的，编译时从 `fw0.koolcenter.com` 下载（4.2.2，hash 固定）；装好后 `/usr/sbin/ddnstod`。

---

## 5. 集客软 AC 控制器

**位置**：LuCI → 服务 → 集客 AC

- 这台机器变成集客 AP 的 AC：集客 AP（需 8.x 固件）指向这台 AC 的 IP 即可被管理。
- 主程序 `/usr/bin/gecoosac`，arm64 二进制约 16MB，配置在 `/etc/config/gecoosac`，证书目录 `/etc/gecoosac/tls`。
- 界面用的是 laipeng668 的 JS 增强版（v2.2.20251015），原版 lwb1978 的仓库已被作者删除。
- 提醒：闭源二进制只保证在对应 CPU 架构能跑（这里是 arm64），跑不起来改不了；另外它占空间，flash 紧的机型要算好固件体积。

---

## 6. 无无线（NOWIFI）版本额外说明

NOWIFI 版本里**没有** `kmod-ath11k` / `wpad` / `hostapd`，所以：

- LuCI 里不会有「无线」菜单项（没有无线设备可管），这是正常的；
- 不会有 `phy0`/`phy1` 之类的无线接口，`iwinfo` 也看不到；
- 想恢复无线只能重新刷 WiFi 版本（不是加个包就能回来的，因为驱动是编进镜像的）；
- 板级校准数据（`ipq-wifi-*`）仍然在镜像里（它不依赖驱动、只有几百 KB），换回 WiFi 版时不用重刷校准分区。

> 补充：`ath11k-firmware-ipq6018` 来自 `ipq60xx/target.mk` 的 `DEFAULT_PACKAGES`，NOWIFI 版目前**没有**关它。
> 它只是固件 blob，没有驱动加载不了，不影响「无无线」的结论；想彻底清干净就在 `config/nowifi.config` 里加
> `# CONFIG_PACKAGE_ath11k-firmware-ipq6018 is not set`。

---

## 7. HomeProxy（sing-box 前端）

**位置**：LuCI → 服务 → HomeProxy

- 由 `scripts/prepare-feeds.sh` 从 `immortalwrt/luci` 的 `applications/luci-app-homeproxy` 取来，
  运行时依赖 `sing-box`（同样从 `immortalwrt/packages` 的 `net/sing-box` 取）。
- 第一次启动会去拉规则集/资源（`/etc/homeproxy/resources/`、`/etc/homeproxy/ruleset/`），
  **必须能出网**；离线环境会卡在「正在下载」。
- 走 nftables TPROXY（依赖 `kmod-nft-tproxy`），和 firewall4 是一套；NSS 卸载对 tproxy 流量不生效，
  代理跑满 CPU 属于正常，别拿 NSS 的 CPU 占用去要求它。
- sing-box 的 NaiveProxy 出站需要 `libcronet`，本树没有这个包，所以 `CONFIG_SING_BOX_BUILD_NAIVE_OUTBOUND`
  是关掉的；其余协议（VLESS/VMess/Trojan/Hysteria2/Shadowsocks/WireGuard）都在。
- 二进制 `sing-box` 是 Go 编译的，约 20~30MB，加上规则集，**flash 紧张的机型要留意体积**。

---

## 8. USB / 外接存储

镜像里带了：`kmod-usb-storage(-uas/-extras)`、`kmod-fs-{ext4,vfat,exfat,ntfs3,btrfs}`、
`kmod-nls-{cp437,iso8859-1,utf8}`、`block-mount`、`dosfstools`、`e2fsprogs`、`btrfs-progs`、
`smartmontools`、`usbutils`，以及 USB 串口（CH340/CP210x/FTDI/PL2303）、USB 网卡（CDC-ECM/RNDIS/ASIX）、
HID、打印机。

```sh
lsusb                       # 看设备有没有被认出来
dmesg | tail -30            # 没认出来先看这里（供电不足/线材问题最常见）
block info                  # 看分区和文件系统
mount /dev/sda1 /mnt        # 手动挂；想自动挂就在 LuCI「系统→挂载点」里配
```

- 自动挂载由 `block-mount` 的 fstab 管，热插拔后一般 3~5 秒出现在 `/mnt/sda1`。
- exFAT/NTFS 用内核驱动（`kmod-fs-exfat` / `kmod-fs-ntfs3`），不需要 fuse，也不吃 CPU。
- 移动硬盘供电不足会反复掉盘：优先用带供电的硬盘盒或 USB Hub。

---

## 9. DiskMan 磁盘管理

**位置**：LuCI → 系统 → 磁盘管理

- 分成「磁盘」「分区」「挂载点」三块，能分区、格式化（ext4/fat32/exfat/ntfs3/btrfs）、
  挂载、看 SMART。**软 RAID（mdadm）默认关闭**，原因在下面。
- 格式化前**确认盘符**：`/dev/sda` 是整盘，`/dev/sda1` 是分区，选错等于格掉整块盘。
- 本固件的根分区是 squashfs + overlay，DiskMan 里显示为一堆只读分区是正常的，不要动 `rootfs_data`。
- SMART 只对 SATA/USB 桥支持良好的硬盘盒有效，很多廉价硬盘盒不转发 SMART 命令。

> **为什么关了 RAID**：DiskMan 的 mdadm 选项会把 `kmod-md-mod` / `kmod-md-raid456` /
> `kmod-md-linear` 拖进来，而 LibWrt 25.12 当前内核（6.12.108）里 `kmod-md-mod` 打包会失败：
> 它要装 `drivers/md/md-mod.ko`，但内核既没生成这个 `.ko`、`modules.builtin` 里也没有，
> 于是 `ERROR: module 'drivers/md/md-mod.ko' is missing.` 直接把整个编译打断。
> 这台机器没有双盘位，RAID 本来也用不上。真要开，得在
> `target/linux/qualcommax/config-6.12` 里补上 `CONFIG_BLK_DEV_MD=m`（属于改上游，不建议）。

---

## 10. LED 配置

**位置**：LuCI → 系统 → LED 配置

- 页面本身由 `luci-mod-system` 提供，本固件额外带了这几个触发器模块，页面上才有对应的「触发模式」：
  `kmod-ledtrig-netdev`（网口活动）、`kmod-ledtrig-timer`（定时闪烁）、`kmod-ledtrig-heartbeat`（心跳）、
  `kmod-ledtrig-default-on`（常亮）、`kmod-ledtrig-transient`、`kmod-usb-ledtrig-usbport`（USB 读写）。
- 想用「网络设备活动」，触发器里填的网口名必须是 `br-lan` / `wan` 这种**真实接口名**，不是 `eth0` 猜想值；
  用 `ip link` 或 `ls /sys/class/net` 确认。
- 三个机型（AX5 / ZN-M2 / NN6000 v2）的 LED 名称各不相同，删掉默认配置后如果灯全灭，
  在「LED 配置」里点「添加」重新绑 GPIO 即可，不需要改 DTS。

---

## 11. 定时重启

**位置**：LuCI → 服务 → Scheduled Reboot（定时重启）

- 配置在 `/etc/config/autoreboot`，本质是往 `/etc/crontabs/root` 里写一条 cron，到点执行 `reboot`。
- 建议错开整点（比如 `04:17`），避免和上游定时任务/更新撞在一起。
- NOWIFI 版同样带这个插件（它不依赖无线）。
- 想临时停一次：页面里关掉开关并「保存应用」，cron 条目会被清掉。

---

## 12. iStore 排错：能拉下来却编不进去

iStore 的包在 feed 里的位置和别的不一样（官方仓库是 `luci/luci-app-store`，多一层目录），
所以「`feeds update` 成功」不等于「包进固件了」。按下面顺序看：

| 现象 | 说明 |
| --- | --- |
| `feeds install -p istore luci-app-store` 报 `No feed for package` | feed 索引没建成，通常是 `feeds update` 那步网络失败；脚本会自动回退到 `kenzo` feed |
| 安装成功但 `tmp/.config-package.in` 里没有 `config PACKAGE_luci-app-store` | Makefile dump 失败，看 `/tmp/tmpinfo.log` 和 `logs/feeds/istore/luci-app-store/dump.txt` |
| 符号在、`.config` 里却没 `=y` | 依赖没满足（`luci-lib-taskd` / `taskd` / `luci-lib-xterm` 缺一个），`verify-config.sh` 会把 `depends on` 打出来 |
| 装上了但页面白屏 | 镜像里缺 `luci-compat` / `luci-lua-runtime`，或浏览器缓存；先强刷 |

本工程的做法：`prepare-feeds.sh` 先试官方 `istore` feed、失败回退 `kenzo`（两边是同一份代码，git tree 相同），
`verify-config.sh` 再把「源码没拉到」和「拉到了但没选上」分开报，`strict_thirdparty=yes` 时直接停在这一步，
不会让你等 3 小时才发现商店没进去。

---

## 13. 流量统计（nlbwmon）

**位置**：LuCI → 统计 → 带宽监控（nlbwmon）

- 按 **每台设备** 累计流量，数据走内核 netlink 记账，**流量被 NSS 硬件卸载了也照样统计得到**，
  这是它比 `vnstat`/`iftop` 更适合这套固件的原因（后者看的是 CPU 侧的接口计数）。
- 数据库在 `/var/lib/nlbwmon/`（内存盘），重启丢；想长期留就把「数据库目录」改到 `/etc/nlbwmon` 或 U 盘，
  注意定期清理，数据量会慢慢涨。
- 页面上的「立即刷新」不会立刻出数据，默认 30 分钟聚合一次。
- 想按天/按周看，下面的 `luci-app-vnstat2`（按接口）和它互补，按需再装。

## 14. 分区扩容（partexp）

**位置**：LuCI → 系统 → 分区扩容

- 用途：装完系统后把没用到的空间并进 overlay（`/overlay`），免得 `/` 只剩几 MB 装不了东西。
  **NN6000 v2 是 eMMC 机型，这个最有用**；AX5 / ZN-M2 是 NAND，收益有限。
- 用法：打开页面 → 选中要扩的分区 → 填目标大小 → 执行，然后**必须重启**才生效。
- 风险：它动的是分区表，操作前先在「备份/升级」里备份配置；刷机不受影响（重刷会重建分区）。
- 如果页面里看不到分区，通常是 `parted` 没装上（`opkg list-installed | grep parted`），
  说明这个包没编进去——看 `verify-config.sh` 的 `[缺失] luci-app-partexp` 那一行。

## 15. Docker（dockerman，只有 eMMC 机型类默认开）

机型按存储分两类：`nand`（AX5 / ZN-M2）**不带** Docker；`emmc`（AX5 JDC / NN6000 v2）**默认带**。
开关来自调用方 matrix 的 `docker` 字段（传给 `_build.yml` 的 `enable_docker`），
手动触发时也可以用 `device_class` 只编 `nand` 或 `emmc` 一类。

体积账（解压后）：

| 组件 | 解压后 |
| --- | --- |
| dockerd | ~25MB |
| containerd | ~18MB |
| docker CLI | ~10MB |
| runc / tini / cgroupfs-mount | ~5MB |

加起来约 60MB。AX5 / ZN-M2 是 **128MB flash**，再加上 sing-box（~20MB）和集客 AC（16MB）必然放不下；
NN6000 v2 带 eMMC 才比较从容。所以做成独立开关，要就给 `enable_docker=yes`。

- 打开后：LuCI → Docker（`luci-app-dockerman`），默认数据目录 `/opt/docker`，
  **先确认 `/opt` 挂到了 U 盘或 eMMC 上**，否则镜像跑两次就写满 rootfs。
- 依赖里带 `iptables`/`kmod-ipt-nat`（Docker 自己要用）+ `kmod-veth`、`kmod-nf-ipvs`，
  这些会和 firewall4(nftables) 共存在一套内核上，一般没事，但开 Docker 后别再去动防火墙的自定义规则。
- 编译时间：dockerd/containerd/runc/docker 是四个 Go 项目，首次编译大概多 30~40 分钟，
  而且 dockerd 的 `Build/Prepare` 会去 GitHub 校验 commit，**网络不稳会直接编译失败**（重跑即可）。
- 真要在 IPQ6000 上跑容器，建议只用 `/opt` 挂 U 盘 + 两三个轻量镜像，别指望当 NAS 主机。

---

## 18. eMMC 寿命检测（只有 eMMC 机型有）

eMMC 机型的镜像里带了 `mmc-utils` 和一个小工具 `emmc-health`，nand 机型没有（`device_class=nand`
时 `base.config` 的 EMMC 段会被整段剔除，因为 `/dev/mmcblk0` 根本不存在）。

### 用法

```sh
emmc-health            # 看当前状态
emmc-health --warn     # 只在异常时输出，给 cron 用
```

输出示例：

```
设备        : /dev/mmcblk0
Pre-EOL     : Normal（正常）   [0x01]
寿命估计 A  : 已用 0% ~ 10%   [0x01]
寿命估计 B  : 已用 0% ~ 10%   [0x01]
累计写入    : 3.42 GiB（自开机以来）
overlay 占用: 1.1G/14G (8%)
结论        : 健康
```

### 这几个字段是什么

| 字段 | 含义 | 什么时候该慌 |
| --- | --- | --- |
| `Pre-EOL` | 厂商预设的寿命阈值状态 | `0x02` 预警（已达 80%）、`0x03` 紧急（耗尽） |
| `寿命估计 A/B` | JEDEC 定义的已用寿命区间，A/B 是两个存储块各自的口径 | 到 `0x0A`（90~100%）该换机，`0x0B` 已超额定 |
| 累计写入 | `/sys/block/mmcblk0/stat` 的写扇区数，**每次重启归零** | 只用来估日常写入量，不是终身累计 |

底层就是 `mmc extcsd read /dev/mmcblk0`，直接从 eMMC 的 EXT_CSD 寄存器读，**不需要拆机、不需要 SMART**。

### 自动检查

首次启动会写一条 cron（`/etc/uci-defaults/97-emmc-weekly-check`）：

```
30 4 * * 6 /usr/bin/emmc-health --warn | logger -t emmc-health
```

每周六 04:30 跑一次，只有在 `Pre-EOL ≥ warning` 或寿命 ≥ 90% 时才往 syslog 写一条，
LuCI → 状态 → 系统日志里搜 `emmc-health` 就能看到。**正常时不产生任何输出和日志**。

> 注意：这条 cron 写在 `/etc/crontabs/root` 里。如果你之后在 LuCI「计划任务」里保存过一次，
> 它可能被覆盖 —— 那样的话把上面这行重加一次即可。

### 和 Docker 的关系

Docker 在 eMMC 机型上是默认开的（`enable_docker=auto`），而容器的写放大是 eMMC 寿命的最大敌人：

- `/opt/docker` 默认就在 eMMC 上，镜像层、容器日志都会持续写入；
- 有条件的话把 `/opt` 挂到 U 盘/SSD（LuCI → 挂载点），eMMC 只放系统；
- 至少给 dockerd 的日志加个上限，别让它无限长（`/etc/docker/daemon.json` 里
  `"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"2"}`）。

顺带一句：`nand` 机型的 flash 是 NAND，没有这套寄存器，也就没有寿命检测——128MB 的机器
本来也不适合跑 Docker，所以 `device_class=nand` 时 Docker 默认是关的。

---

## 19. CoreMark 跑分

来自官方 packages feed 的 `utils/coremark`，装完就是 **`/bin/coremark`**（几十 KB，两个类都带）。

### 用法

```sh
coremark                 # 跑一次标准测试（单核，默认 50000 次迭代）
coremark -v              # 带详细输出
```

关心的就一行：

```
CoreMark 1.0 : 8721.35 / GCC 14.3.0 (-O3) / heap
```

这个 `8721.35` 就是 **iterations/sec**，数值越大越好。Cortex-A53 大约 **每 MHz 2.5~3.5 分**
（受 GCC 版本和优化影响），所以 IPQ6000 @1.5GHz 单核大致落在 **4000~6000** 这个量级；
拿到 8000 以上说明优化特别到位（LTO + O3），明显低于 3000 就要怀疑是不是没开 `-O3`
或者测试时有别的负载在抢 CPU，可以用「分数 ÷ 1500MHz ≈ 每 MHz 得分」自己验算一下。

### 我们编进去的参数

| 配置 | 值 | 原因 |
| --- | --- | --- |
| `COREMARK_OPTIMIZE_O3` | y | 不加 `-O3` 分数会低 30% 以上，横向对比就失真了 |
| `COREMARK_ENABLE_MULTITHREADING` | **n** | 官方榜单都是单核成绩；开多线程得到的是“总吞吐”，不能直接和别人比 |
| `COREMARK_NUMBER_OF_THREADS` | 不用 | 关多线程时它不生效 |

想要多核吞吐：把 `CONFIG_COREMARK_ENABLE_MULTITHREADING=y` 和
`CONFIG_COREMARK_NUMBER_OF_THREADS=4` 打开重编，得到的分数约等于单核 × 4 × 效率，
**不要**拿去和单核分数比。

### 两个坑

1. **别在跑满流量时测**。NSS 卸载后 CPU 空闲，但 P2P/大流量时软中断会抢 CPU，分数能掉一半。
   测之前先 `uptime` 看负载，最好在 `0.00` 左右。
2. **opkg 事后安装会加一条 04:00 的 cron**。这个包的 `postinst` 会往 `/etc/crontabs/root` 写
   `0 4 * * * /etc/coremark.sh`（每天凌晨跑一次并写日志）。编进固件时因为 `IPKG_INSTROOT` 存在，
   这段不会执行；但如果你是刷完机用 opkg/iStore 装的，记得删掉：
   ```sh
   sed -i '/coremark/d' /etc/crontabs/root && /etc/init.d/cron restart
   ```

### 和其他型号对比的建议

同一个固件、同一版 GCC、同样 `-O3` 才有可比性。换个 `source_branch`、换个 GCC 版本，
分数变化 10% 很正常——所以这个数字更适合“自己前后对比”（比如加了 NSS 某个补丁之后有没有变），
而不是拿去做跨品牌跑分。

### 定时跑分

固件自带一个定时任务，每天 04:00 自动跑一次并把成绩记进 `/root/coremark-history.txt`。

```sh
coremark-bench                 # 手动跑一次，打印成绩并记录
coremark-bench --last 20       # 看最近 20 次
/etc/init.d/coremark-bench status   # 看配置 / crontab 里的定时行 / 最近 3 次
```

| 文件 | 作用 |
| --- | --- |
| `overlay/usr/bin/coremark-bench` | 跑分 + 解析 + 记历史（保留最近 60 条） |
| `overlay/etc/init.d/coremark-bench` | 把带标记的一段 cron 写进 `/etc/crontabs/root` |
| `overlay/etc/config/coremark-bench` | `enabled`、`schedule` 两个选项 |
| `overlay/etc/uci-defaults/97-coremark-bench` | 首次启动 enable |

改时间或关掉：

```sh
uci set coremark-bench.settings.schedule='30 3 * * *'   # 每天 03:30
uci set coremark-bench.settings.enabled='0'             # 关掉，从 crontab 撤掉这一段
uci commit coremark-bench
/etc/init.d/coremark-bench reload
```

几个设计上的取舍：

1. **只维护自己那段 cron**。`/etc/crontabs/root` 里用 `# >>> coremark-bench` / `# <<< coremark-bench`
   包起来，其它行（你自己加的定时任务）原样保留，重复执行也不会堆叠。
2. **历史存在 `/root`，不是 `/tmp`**。`/tmp` 重启就没，而跑分的意义恰恰是「和上周比」。
   `/root` 在 overlay 上，sysupgrade 默认保留；一天一行，对 flash 的磨损可以忽略。
3. **掉 20% 会自己报警**。成绩低于上次的 80% 时往 syslog 写一条，专门用来抓
   「散热降频 / 后台有活 / 某个补丁把优化改坏了」这类问题：`logread | grep coremark-bench`。
4. **不要在白天跑**。CoreMark 单核满跑十几秒，期间那一个核会被吃满；04:00 默认值就是为此选的，
   和 eMMC 周检（每周六 04:30）也错开了，两者不会撞车。

> 在 LuCI「计划任务」里手工保存过一次的话，会整份重写 `/etc/crontabs/root`，我们那段可能被冲掉；
> 重启一次服务就回来了：`/etc/init.d/coremark-bench reload`。

### 多核跑分与 CPU 频率（2026-11 补）

固件默认改成：

- **CoreMark 编成多线程**（4 线程），一个二进制能自选核数：
  `coremark -c 1` 单核、`coremark -c 4` 四核（`coremark-bench` 默认跑满 4 核）；
- **板级 dts 补了 1320 / 1440 / 1512 MHz 三档 OPP**，构建时由
  `scripts/patch-cpu-opp.sh` 自动打，编译参数 `cpu_boost=no` 可关掉。

为什么原来只有最高 1200：上游内核 `ipq6018.dtsi` 的 `cpu_opp_table` 只定义了
864 / 1056 / 1200 三档，而 LibWrt 的 `ipq6018-common.dtsi` 里给 1320/1440/1512
只写了 `opp-supported-hw`、**没写 `opp-hz`** —— 节点是空的，`cpufreq-dt` 直接跳过。
板级 dts 里补一个 `opp-hz` 就够了（电压由 CPR / board 决定）。

验证：

```sh
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
# 期望：864000 1056000 1200000 1320000 1440000 1512000
```

分数参考（-O3 + LTO，单核约 3.3~3.5 分/MHz）：

| 频率 | 单核 | 四核 |
| --- | --- | --- |
| 1200 MHz | ~4010 | ~13000 |
| 1512 MHz | ~5060 | ~17000 |

风险：1512 是原厂档位（b佬的固件也在跑），但体质和散热因机器而异。
不想要就在编译时选 `cpu_boost=no`，回到最高 1200MHz。

---

## 20. 连接跟踪（conntrack）与 QUIC

### 为什么抖音 / 红果会把表顶满

这两个都是字节系，视频全走 **QUIC（UDP/443）**。UDP 没有挥手包，客户端关页面时路由器是不知道的，
只能靠超时回收：

| 机制 | 默认值 | 后果 |
| --- | --- | --- |
| `nf_conntrack_udp_timeout_stream` | 180 秒 | 双向有流量的 UDP 条目要躺 3 分钟 |
| `nf_conntrack_udp_timeout` | 30 秒 | 只发不收的残留 |
| `nf_conntrack_max` | **不随内存变化** | 2G / 1G / 256M 读到的是同一个数，常见 16384 或 65536 |

外加每换一个视频分片、每换一个 CDN 节点就是一条新五元组，几台设备一起刷就能把表填满。
**所以「内存 2G 还是爆表」不是内存不够，是上限根本没跟着内存走。**

爆表之后的症状：`dmesg` 里 `nf_conntrack: table full, dropping packet`，新连接建不起来，
表现为刷视频转圈、网页打不开，过一会儿（旧条目超时了）自己恢复。

### 固件里做了什么

| 文件 | 作用 |
| --- | --- |
| `overlay/etc/init.d/conntrack-tune` | 开机（S15，先于 firewall）套用调优参数，可选生成 QUIC 封禁规则 |
| `overlay/etc/config/conntrack` | UCI 配置，所有开关都在这里 |
| `overlay/etc/uci-defaults/98-conntrack-tune` | 首次启动把服务 enable 进 rc.d |
| `overlay/etc/modprobe.d/99-nf-conntrack.conf` | 尽力把哈希桶设成 65536（模块先被加载的话这项不生效） |

默认值（都可在 `/etc/config/conntrack` 里改）：

| 参数 | 默认 | 2G（NN6000） | 1G（ZN-M2） | 其它（AX5） |
| --- | --- | --- | --- | --- |
| `nf_conntrack_max` | `auto` | 262144 | 131072 | 65536 |
| `nf_conntrack_udp_timeout` | 15 | — | — | — |
| `nf_conntrack_udp_timeout_stream` | 60 | — | — | — |
| `nf_conntrack_tcp_timeout_established` | 3600 | — | — | — |

`auto` 是按 `/proc/meminfo` 的 MemTotal 现场算的，不用手填。
表项是**按需分配**的，把上限写大不会立刻吃内存（每条约 300~400 字节，顶满才占）。

> `udp_timeout` 从 30 缩到 15，代价是「不常发保活包的 UDP 应用」NAT 映射会散得快一点。
> 主机联机游戏如果出现 NAT 变严格、进不去房，把它调回 30 再试：
> `uci set conntrack.settings.udp_timeout=30`。`udp_timeout_stream` 才是对付 QUIC 的主力，
> 它不受这个影响。

### 用法

```sh
/etc/init.d/conntrack-tune status       # 当前条目数 / 上限 / QUIC 封禁状态
/etc/init.d/conntrack-tune restart      # 改完配置重载

uci set conntrack.settings.max=131072 ; uci commit conntrack
```

### 可选：按设备封 QUIC

```sh
uci set conntrack.quic.enabled=1
uci add_list conntrack.quic.mac='aa:bb:cc:dd:ee:ff'
uci commit conntrack
/etc/init.d/conntrack-tune restart
```

规则是 `table inet conntrack_guard` 里 `prerouting priority raw` 的那条，
匹配 `ether saddr` 后丢掉 `udp dport 443`。**位置很关键**：

| 放在哪 | conntrack 表项 | 代价 |
| --- | --- | --- |
| LuCI 自定义规则（`fw4` 的 forward 链） | **照建不误**：先建表再丢 | 表没省下来，CPU 还多了一次丢弃 + 客户端重试 |
| 本固件的 `prerouting/raw`（-300，早于 conntrack 的 -200） | 一条都不建 | 只有一次 set 查找 |

### 两个坑

1. **封 QUIC 会让 CPU 忙起来**。客户端 QUIC 失败后会不停重试、并回落 TCP，包量翻倍。
   表现是 CPU 偶尔冲到 50%，同一台路由器后面的游戏出现 1~2 秒的丢包抖动。
   所以默认是关的，只建议对电视/旧手机开，**游戏机别进列表**。
2. **MAC 匹配有前提**。设备必须和路由器在同一个二层（直连或桥接的 AP）。中间再过一层
   路由器（双重 NAT）就匹配不到了，那种情况只能改成按 IP 匹配。

### 验证到底有没有用

```sh
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max
dmesg | grep -i "table full"
```

跑一天之后看 `nf_conntrack_count` 的**峰值**：如果离 max 还有一半以上的余量，说明调够了；
如果天天贴着 max，要么继续往上调一档，要么打开 QUIC 封禁（只对电视）。

---

## 21. 测速（luci-app-netspeedtest）

作者 sirpdboy，仓库 [sirpdboy/netspeedtest](https://github.com/sirpdboy/netspeedtest)。
一个页面把内网和外网测速都包了，省得 SSH 里敲 iperf3。

### 装的是哪三块

| 包 | 作用 |
| --- | --- |
| `luci-app-netspeedtest` | LuCI 页面：**网络 → NetSpeedtest** |
| `homebox` | 内网测速服务端（预编译二进制，浏览器打开就有图形界面） |
| `ookla-speedtest` | 外网测速 CLI（Speedtest.net 官方客户端） |

页面下五个子页：`Iperf3`、`Homebox`、`Wan SpeedTest`、`Online SpeedTest`、`Log`。

依赖会顺带把 `iperf3`、`jq`、`python3-light` 和几个 python3 模块拉进来——
**这一套 15~20MB**，所有机型都带。

> 一开始我把它限定在 eMMC 机型，是怕 128MB flash 的 nand 机型塞不下；
> 实测这几个机型的镜像是 **30~50MB**（`sysupgrade` / `factory` / `.itb` 都不到 128MB），
> 加完这一套还有富余，所以现在默认全机型都编进去。
> `collect-firmware.sh` 会打印每个镜像的实际大小，超过 60MB 打 warning。

### 怎么用

**内网（Iperf3 页）**：路由器当服务端，页面里点「启动」，然后电脑/手机跑客户端：

```sh
iperf3 -c 192.168.10.254 -t 30 -P 4        # 上行
iperf3 -c 192.168.10.254 -t 30 -P 4 -R     # 下行
```

**内网（Homebox 页）**：在页面上打开服务（默认端口 3300），然后用**手机浏览器**访问
`http://192.168.10.254:3300`，点「开始」就测——另一头不用装任何东西。家里没人会敲命令时用这个。

**外网（Wan / Online 页）**：直接选服务器跑 Ookla，出的是对运营商的上下行。

### 三个坑

1. **两个二进制是构建时下载的**。`homebox` 从 sirpdboy/homebox 的 release 拉，`ookla-speedtest`
   从 `install.speedtest.net` 拉，Makefile 里写死了 `PKG_HASH`。上游换包 → 哈希对不上 → **整个 job 直接失败**。
   真遇到了就把 `NETSPEEDTEST` 段注释掉重编，或者临时设 `enable_thirdparty=no` 先出个固件。
2. **测的是路由器自身，不是转发**。iperf3/homebox 的流量由路由器本机产生/接收，走的是 CPU 协议栈，
   NSS 快传不参与。想看 NAT 转发能力，得让流量**穿过**它（两台终端一左一右）。
3. **`netspeedtest.sh` 是 bash 脚本**，而 OpenWrt 默认只有 ash。WAN 测速那部分如果报
   `not found` / 语法错，装个 `bash` 即可：`apk add bash`。内网 iperf3/homebox 不依赖它。

### 怎么关

删掉 `config/base.config` 里 `# >>> NETSPEEDTEST-BEGIN` 到 `# <<< NETSPEEDTEST-END` 那三行；
或者编译时把 `enable_thirdparty` 设成 `no`（测速段会跟着第三方段一起剔掉）。
只想保留 CLI 不要页面：`apk add iperf3` 就够，不需要这一套。
- **只删页面留 CLI**：`apk add iperf3` 就够，不需要这套（见上一节的说明）。





