# IPQ6000 满血 NSS 云编译（WiFi / NOWIFI 两版 + 6.18 实验线）蓝色大肥鱼完全控制编译版

红米 AX5、兆能 ZN-M2（`redmi_ax5` / `zn_m2`，128MB NAND）和 Link NN6000 v2（`link_nn6000-v2`，eMMC）的 GitHub Actions 编译工程。

一次编译产出**两套可选固件**：

| 版本 | Workflow | 无线 | 体积 | 适用 |
| --- | --- | --- | --- | --- |
| **WiFi 版** | `Build IPQ6000 WiFi` | ath11k + wpad + NSS 无线卸载 | 大一些 | 当无线主路由用 |
| **NOWIFI 版** | `Build IPQ6000 NOWIFI` | **镜像里不含 ath11k/wpad/hostapd，开机不可能起无线** | 小一些 | 纯有线路由 / 旁路由 / 集客 AC 主机 |

机型按**存储类型**分两类并行编译（`device_class` 可选 `all` / `nand` / `emmc`）：

| 类 | 机型 | 存储 | Docker | eMMC 寿命检测 |
| --- | --- | --- | --- | --- |
| `nand` | `redmi_ax5`、`zn_m2` | 128MB NAND | **不带**（放不下） | 无（NAND 没这套寄存器） |
| `emmc` | `link_nn6000-v2` | eMMC 3.69G | **默认带** | **有**：`emmc-health` + LuCI 页面 + 每周自检 |

> 红米 AX5 JDC（`redmi_ax5-jdcloud`）已从 eMMC 类移出，现在 eMMC 类只编 NN6000 v2。
> 为什么拆两类而不是一个 job 编全部：Docker 的 `CONFIG_PACKAGE_docker=y` 是全局的，
> 想只给 eMMC 机型加，只能用 `CONFIG_TARGET_DEVICE_PACKAGES_*` + `TARGET_PER_DEVICE_ROOTFS=y`，
> 而那会跟 NOWIFI「在 `.config` 里关掉 ath11k」的做法打架。拆 job 还顺带避开了 6 小时上限。

两版共用同一个可复用工作流，差异只在 `config/wifi.config` 和 `config/nowifi.config`，不会出现「改了 A 忘了改 B」。

两版都带：**满血 NSS（NSS 11.4）+ miniupnpd(UPnP) + iStore + 微信推送 + DDNSTO + 集客软 AC
+ Vantage 主题 + CPU 性能调节 + 终端(ttyd) + CoreMark 跑分**，
以及按内存分档的 **conntrack 调优**（防抖音/红果刷爆表）和 **测速页**
（`luci-app-netspeedtest`：网络 → NetSpeedtest，内网 iperf3 / Homebox + 外网 Ookla）。

各插件怎么用见 [docs/PLUGINS.md](docs/PLUGINS.md)：跑分看第 19 节，conntrack 看第 20 节，测速看第 21 节。

---

## 一、两条线，别混

| | **6.12 主线** | **6.18 实验线** |
| --- | --- | --- |
| 源码 | LibWrt `25.12-nss` | `VIKINGYFY/immortalwrt` 的 `owrt` 分支 |
| 内核 | 6.12 | 6.18.60 |
| 卸载 | NSS 11.4 | **NSS 12.5 + PPE 双卸载** |
| 机型 | AX5 / ZN-M2 / NN6000 v2 | NN6000 v2（eMMC）+ AX5 / ZN-M2（NAND） |
| Workflow | `Build IPQ6000 WiFi` / `Build IPQ6000 NOWIFI` | `Build NN6000 6.18 (NSS+PPE)` / `Build AX5/ZN-M2 6.18 (NSS+PPE, NAND)` |
| Release tag | `ipq6000-<变体>-<类>-<时间>` | `nn6000-618-<时间>` / `nand618-<时间>-<机型>` |
| 定位 | 日常用，稳 | 试新，PPE 卸载验证 |

两条线互相独立：6.18 改坏了不影响 6.12，镜像也分开命名。

---

## 二、目录结构（各司其职）

```
.
├── .github/workflows/
│   ├── _build.yml                # 6.12 主线可复用流程（被下面两个入口调用）
│   ├── build-wifi.yml            # 6.12 入口：WiFi 版（手动）
│   ├── build-nowifi.yml          # 6.12 入口：NOWIFI 版（手动 + 每周六自动）
│   ├── build-nn6000-618.yml      # 6.18 入口：NN6000 v2（eMMC，带 Docker/HomeProxy）
│   ├── build-618-nand.yml        # 6.18 入口：AX5 + ZN-M2（NAND，精简）
│   └── cleanup.yml               # 清理历史 Release / 运行记录
├── config/
│   ├── base.config               # 6.12 公共：机型 + NSS + 界面 + UPnP + 第三方插件段
│   ├── wifi.config / nowifi.config
│   ├── nn6000-618.config         # 6.18 eMMC（NN6000 v2）完整插件集
│   ├── nn6000-618-nand.config    # 6.18 NAND（从上面派生，砍掉放不下的）
│   └── feeds.extra.conf          # 第三方 feed：kenzok8、集客AC、微信推送
├── packages/
│   └── luci-app-emmc-health/     # 自建 LuCI 包：状态 → eMMC 健康（两条线共用）
├── scripts/
│   ├── prepare-feeds.sh          # 拉官方 feeds + 第三方插件 + Vantage 主题
│   ├── prepare-config.sh         # 合并 base + 变体 → .config
│   ├── verify-config.sh          # defconfig 后校验：机型 / 包 / 变体一致性
│   ├── patch-cpu-opp.sh          # 6.12：补 1320/1440/1512MHz OPP
│   ├── patch-dts-keys.sh         # 6.18：删 wps 键，修 GPIO42 冲突（保 reset）
│   └── collect-firmware.sh       # 编译后按机型打包
├── overlay/                      # 并进 base-files 的 rootfs 文件（两条线自动注入）
│   ├── etc/uci-defaults/         # 首次启动：默认 IP、默认主题、conntrack、UPnP 私网映射
│   ├── etc/init.d/               # conntrack-tune（S15，先于 firewall）
│   ├── etc/config/               # conntrack 的 UCI 默认值
│   ├── etc/modprobe.d/           # nf_conntrack 哈希桶（尽力而为）
│   └── usr/bin/                  # emmc-health / coremark-bench
├── docs/
│   └── PLUGINS.md                # 插件配置与限制
└── README.md
```

每个脚本只干一件事，出问题一眼能定位到是哪一步。

---

## 三、怎么用

1. 整个目录推到自己的 GitHub 仓库。
2. **Settings → Actions → General → Workflow permissions** 选 **Read and write**（自动发 Release 需要）。
3. **Actions** 里选对应 workflow → **Run workflow**：

   | 参数 | 默认 | 说明 |
   | --- | --- | --- |
   | `source_repo` | `https://github.com/LiBwrt/LibWrt.git` | 6.12 固件源码 |
   | `source_branch` | `25.12-nss` | NSS 分支 |
   | `extra_packages` | 空 | 再追加包，如 `luci-app-wol` |
   | `enable_thirdparty` | yes | iStore/微信推送/DDNSTO/集客AC/Vantage；编不过就选 no |
   | `strict_thirdparty` | yes | 第三方插件缺失时直接失败（配置阶段就停，不白烧 2~3 小时） |
   | `device_class` | all | `all`=nand+emmc 两个 job 并行；`nand`=AX5/ZN-M2；`emmc`=**NN6000 v2** |
   | `enable_docker` | auto | `auto`=emmc 带、nand 不带；`yes`/`no` 强制 |
   | `publish_release` | yes | 编完自动建 Release |

4. 约 **2～3 小时**（`device_class=all` 时两个 job 并行，不会翻倍）。
   产物在 **Actions → Artifacts**（`ipq6000-wifi-nand-N` / `ipq6000-wifi-emmc-N`）
   或 **Releases**（tag 形如 `ipq6000-nowifi-emmc-20261022-1200`）。

NOWIFI 版每周六 02:00（北京时间）自动编一次；WiFi 版只在手动触发时编，免得每周白烧一次 Actions 额度。

---

## 四、首次开机做了什么（两条线通用）

`overlay/etc/uci-defaults/` 里的脚本只在**全新安装**时生效，规则如下：

| 行为 | 不保留数据升级（`-n`） | 保留数据升级（默认） |
| --- | --- | --- |
| LAN IP 改成 192.168.10.254 + DHCP 池 100-249 | ✅ 会改 | ❌ **完全不动** |
| 默认主题设为 Vantage | ✅ | ❌ 用户自己选过就不覆盖 |
| conntrack 调优 / UPnP 私网映射 / 中文界面 | ✅ | ✅（幂等，重复执行也无害） |

实现方式：在 `/etc/config/.lan_ip_initialized`、`/etc/config/.theme_initialized` 放标记文件。
sysupgrade 保留数据时会带走 `/etc/config`，所以标记跨升级有效；overlay 里的「脚本已执行」删除标记会被丢，所以不能靠它。

想强制重置回默认 IP：`rm /etc/config/.lan_ip_initialized` 后重刷，或直接 `uci set network.lan.ipaddr=...`。

---

## 五、产物与刷机

```
libwrt-qualcommax-ipq60xx-redmi_ax5-squashfs-sysupgrade.bin
libwrt-qualcommax-ipq60xx-zn_m2-squashfs-sysupgrade.bin
libwrt-qualcommax-ipq60xx-link_nn6000-v2-squashfs-sysupgrade.bin
```

（同一次编译还会出 `factory.bin` / `*.itb` / `*.ubi`，`机型-files.txt` 里列全。）

**什么时候刷哪个**：

| 场景 | 用哪个文件 | 怎么刷 |
| --- | --- | --- |
| 机器已经在跑 OpenWrt | `*-squashfs-sysupgrade.bin` | 系统里 `sysupgrade -n 文件`，或 LuCI「系统 → 备份/升级」 |
| 第一次刷（原厂 / 砖了 / 换系统） | `factory.bin`（eMMC 机型）、`*.itb`（NAND 机型） | uboot 的 Web 恢复页或 tftp |

**别混着用**：`sysupgrade.bin` 是给系统内的升级程序吃的，uboot 不认；`factory.bin` / `.itb`
是给 uboot 的，拿到系统里刷会把分区写歪。

**固件版本里带编译时间**：

- 6.12 主线：`25.12-nss+nand.20261022-1630`（`<分支>+<机型类>.<北京时间>`），另有 `/etc/build-info`；
- 6.18 线：`6.18-20261121-0200-<源码commit>`，在 LuCI 概览页「固件版本」直接可见。

- 已在跑 OpenWrt：`sysupgrade -n 文件`（换源建议不保留配置）。
- 第一次刷（原厂 / uboot 下）：刷 `factory.bin` 或 `*.itb`，别拿 `sysupgrade.bin` 去喂 uboot。
- 刷前**备份原厂分区**（尤其 ART/校准分区）。
- **WiFi 版 ↔ NOWIFI 版可以互刷**（同机型 sysupgrade 直接刷），但刷 NOWIFI 后无线就没了，回退要重刷 WiFi 版。

---

## 六、自定义

- **加包**：运行时填 `extra_packages`，或写进对应 `config/*.config`（`CONFIG_PACKAGE_xxx=y`）。
- **只去掉某个第三方插件**：删 `base.config` 里对应两三行；全去掉就把 `enable_thirdparty` 设为 `no`。
- **加机型**：`_build.yml` 的 `plan` job 里 `nand` / `emmc` 两条 `devices` 字符串才是真正生效的地方；
  6.18 线则在 `build-618-nand.yml` 的 `matrix.device` 里加。
- **改无线参数**：只动 `config/wifi.config`。
- **换内核/分支**：改 `source_branch`；分支里没这三个机型时，`verify-config.sh` 会直接报错并列出可用机型。

---

## 七、常见问题

| 现象 | 处理 |
| --- | --- |
| 「当前源码分支不包含机型」 | 分支不对，按日志列出的机型改配置 |
| 「以下软件包没有被选中」 | feeds 没拉到 / 包名变了，日志会列出候选；先设 `enable_thirdparty=no` 出个可用固件 |
| NOWIFI 编出来还有无线 | 不会发生——校验会失败。真失败了看 manifest 里 `wpad` 是谁带进来的 |
| 编译卡在 `ddnsto` 下载 | koolcenter CDN 对海外 IP 抽风，重跑；屡次失败先关第三方插件 |
| iStore 页面空白 | 确认 `luci-compat`/`luci-lua-runtime` 在 manifest 里，或浏览器强刷 |
| 集客 AC 起不来 | 架构不对（必须 arm64）或 flash 放不下 |
| 微信推送没流量数据 | `wrtbwmon` 与 NSS/Flow Offloading 冲突，已知限制 |
| 刷抖音/红果一会儿全网卡几秒 | conntrack 表被 QUIC 顶满。`/etc/init.d/conntrack-tune status` 看水位；UDP 超时默认 20/60 |
| 6.18 上视频卡顿、`PPE: 1900/2048` | IPQ6018 的 PPE 流表硬件只有 2048 条，写死在驱动里、不能扩。压连接数，或关 `flow_offloading` 退回软件转发，或换 6.12（NSS 8192 条） |
| 想看跑分 | `coremark-bench --last 20`；`/etc/init.d/coremark-bench status` |
| Releases / 运行记录堆太多 | Actions 里跑 **Cleanup runs & releases**：先 `dry_run=true` 预览，再关掉并填 `DELETE` |
| 找不到「NetSpeedtest」菜单 | 第三方包：`enable_thirdparty=no` 时被剔掉，或 sparse clone 没拉到 |
| 发 Release 403 | Workflow permissions 没给 Read and write |

---

## 八、说明

- NSS 驱动/固件、DDNSTO、集客 AC 都是**闭源二进制**，仅供个人自用。
- 工作流只编译，不改分区表、不加后门，产物 = 标准上游镜像 + 上述插件。
- LibWrt 仓库 400MB+、kenzok8 feed 150MB+，首次 clone 慢属正常。

---

## 九、6.18 实验线（两条 workflow）

源码 `VIKINGYFY/immortalwrt@owrt`：内核 6.18.60 + NSS 12.5 + **PPE 硬件卸载**，机型定义齐全，不用移植 DTS。

| | NN6000 v2（eMMC） | AX5 / ZN-M2（NAND） |
| --- | --- | --- |
| Workflow | `Build NN6000 6.18 (NSS+PPE)` | `Build AX5/ZN-M2 6.18 (NSS+PPE, NAND)` |
| 配置 | `config/nn6000-618.config` | `config/nn6000-618-nand.config` |
| 产物 | ~110MB | ~40MB |
| Release | `nn6000-618-<时间>` | `nand618-<时间>-<机型>` |

**带的东西**：中文界面、Vantage 主题、CPU 性能调节、终端、UPnP、nlbwmon、iperf3、CoreMark、
conntrack 调优、eMMC 健康页面（仅 NN6000）、iStore、DiskMan、微信推送、DDNSTO、集客 AC、USB 存储。

**NN6000 额外带**：Docker（dockerd + dockerman）、**HomeProxy + sing-box**（魔法上网）。

**NAND 机型不带**：Docker、HomeProxy/sing-box、netspeedtest（python3 一套约 20MB）——128MB flash 放不下。

### 6.18 上的两个已知点

1. **reset 键**：设备树里 wps 键占 GPIO42，和 i2c 冲突，导致 `gpio-keys` 整体 probe 失败（reset 也用不了）。
   构建时自动删掉 wps 键（`scripts/patch-dts-keys.sh`），reset 恢复正常。
2. **PPE 流表只有 2048 条**（IPQ6018 硬件规格，驱动里 `.num_flow_entries = 2048` 写死，无 DTS/模块参数可调）。
   IPv4+IPv6 共用这张表，大量 P2P/BT 或长时间挂着几百个 QUIC 流时会接近满，满后表现为丢包/视频卡顿。
   缓解：`conntrack.settings.udp_timeout=20`、`udp_timeout_stream=60`（默认已设），或 `flow_offloading='0'`，或换 6.12 线。

刷完先确认：`uname -r` 是 6.18.x、LuCI 首页 `PPE: x/y` 在涨、`uci get luci.main.mediaurlbase` 是 `/luci-static/vantage`。
