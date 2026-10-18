# 固件里这几个功能怎么用

刷完先确认 NSS 在干活，再看插件。

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
