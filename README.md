# IPQ6000 满血 NSS 云编译（WiFi / NOWIFI 两版）蓝色大肥鱼完全控制编译版

红米 AX5、兆能 ZN-M2、Link NN6000 v2（都是 IPQ6000，均已改 1G 内存）的 GitHub Actions 编译工程。
一次编译产出**两套可选固件**：

| 版本 | Workflow | 无线 | 体积 | 适用 |
| --- | --- | --- | --- | --- |
| **WiFi 版** | `Build IPQ6000 WiFi` | ath11k + wpad + NSS 无线卸载 | 大一些 | 当无线主路由用 |
| **NOWIFI 版** | `Build IPQ6000 NOWIFI` | **镜像里不含 ath11k/wpad/hostapd，开机不可能起无线** | 小一些 | 纯有线路由 / 旁路由 / 集客 AC 主机 |

两版共用同一个可复用工作流，差异只在 `config/wifi.config` 和 `config/nowifi.config`，不会出现「改了 A 忘了改 B」。

两版都带：**满血 NSS（NSS 11.4）+ miniupnpd(UPnP) + iStore + 微信推送 + DDNSTO + 集客软 AC**。
各插件怎么用见 [docs/PLUGINS.md](docs/PLUGINS.md)。

---

## 一、先说清楚「6.18」

1. OpenWrt 官方 main 的 `qualcommax/ipq60xx` **确实是 Linux 6.18**，但它**没有** `redmi_ax5` / `zn_m2` / `link_nn6000-v2` 这三个机型，也**不带 NSS 硬件卸载**。
2. 真正「6.18 + NSS」的是 `openwrt-ppe-nss` 那类补丁树，同样不含这三款机型。
3. 所以按你选的「稳定优先」，本工程用 **LibWrt `25.12-nss`：内核 6.12 + 满血 NSS**。想出 6.18 时改 `source_branch` 一处即可。

---

## 二、目录结构（各司其职）

```
.
├── .github/workflows/
│   ├── _build.yml          # 可复用工作流（唯一一份完整流程，被下面两个调用）
│   ├── build-wifi.yml      # 触发入口：WiFi 版（手动）
│   └── build-nowifi.yml    # 触发入口：NOWIFI 版（手动 + 每周六自动）
├── config/
│   ├── base.config         # 公共：三机型 + NSS + 界面 + UPnP + 第三方插件段
│   ├── wifi.config         # 变体差异：ath11k / wpad / ATH11K_* 选项
│   ├── nowifi.config       # 变体差异：关掉 ath11k / wpad / hostapd
│   └── feeds.extra.conf    # 第三方 feed：kenzok8、集客AC、微信推送
├── scripts/
│   ├── prepare-feeds.sh    # 拉官方 feeds + 追加第三方 feed + 只装需要的插件
│   ├── prepare-config.sh   # 合并 base + 变体 → .config
│   ├── verify-config.sh    # defconfig 后校验：机型 / 包 / 变体一致性
│   └── collect-firmware.sh # 编译后按机型打包
├── docs/
│   └── PLUGINS.md          # 五个插件的配置与限制
└── README.md
```

每个脚本只干一件事，出问题一眼能定位到是哪一步。

---

## 三、怎么用

1. 整个目录推到自己的 GitHub 仓库。
2. **Settings → Actions → General → Workflow permissions** 选 **Read and write**（自动发 Release 需要）。
3. **Actions** 里选 `Build IPQ6000 NOWIFI`（或 `Build IPQ6000 WiFi`）→ **Run workflow**：

   | 参数 | 默认 | 说明 |
   | --- | --- | --- |
   | `source_repo` | `https://github.com/LiBwrt/LibWrt.git` | 固件源码 |
   | `source_branch` | `25.12-nss` | NSS 分支（换内核改这里） |
   | `extra_packages` | 空 | 再追加包，如 `luci-app-wol` |
   | `enable_thirdparty` | yes | iStore/微信推送/DDNSTO/集客AC；某插件编不过就选 no |
   | `publish_release` | yes | 编完自动建 Release |

4. 约 **2～3 小时**。产物在 **Actions → Artifacts**（`ipq6000-wifi-N` / `ipq6000-nowifi-N`）或 **Releases**（tag 形如 `ipq6000-nowifi-20261018-1200`）。

NOWIFI 版每周六 02:00（北京时间）自动编一次；WiFi 版只在手动触发时编，免得每周白烧一次 Actions 额度。

---

## 四、NOWIFI 到底关了什么

做法和 LibWrt 给「京东云 RE-CS-07（无 WiFi 机型）」的定义一致，关这些：

```
kmod-ath11k  kmod-ath11k-ahb  kmod-ath11k-pci
wpad-openssl（以及 wpad 各变体）  hostapd-common
CONFIG_ATH11K_NSS_MESH_SUPPORT  CONFIG_ATH11K_MEM_PROFILE_512M
kmod-qca-nss-drv-wifi-meshmgr（无线 mesh 卸载模块）
```

我们的三个机型 `DEVICE_PACKAGES` 里只有 `ipq-wifi-*`（板级校准数据，不依赖驱动），所以配置层关掉就够了，不需要改目标 Makefile——升级上游分支也不会打架。

结果：镜像里没有 ath11k 内核模块、没有 wpad，**物理上没有东西能起无线**；LuCI 里也不会有「无线」菜单项（正常现象）。板级校准数据还在镜像里（几百 KB），以后刷回 WiFi 版不需要重做校准。

工作流会对两版分别做**双向校验**：

- WiFi 版：manifest 里必须**有** `kmod-ath11k` / `wpad`，没有就失败；
- NOWIFI 版：manifest 里**出现任何** `kmod-ath11k*` / `wpad*` / `hostapd*` 就失败。

所以不会出现「标着 NOWIFI 其实带着无线」这种乌龙。

---

## 五、产物与刷机

```
libwrt-qualcommax-ipq60xx-redmi_ax5-squashfs-sysupgrade.bin
libwrt-qualcommax-ipq60xx-zn_m2-squashfs-sysupgrade.bin
libwrt-qualcommax-ipq60xx-link_nn6000-v2-squashfs-sysupgrade.bin
```

（不同机型可能还有 `factory.bin` / `*.ubi` 等，`机型-files.txt` 里列全。）

- 已在跑 OpenWrt：`sysupgrade -n 文件`（换源建议不保留配置）。
- 原厂首次刷入：流程按机型不同（uboot Web / breed / 先刷过渡固件），按该机型的 OpenWrt 设备页操作。
- 刷前**备份原厂分区**（尤其 ART/校准分区）。
- **WiFi 版 ↔ NOWIFI 版可以互刷**（同机型 sysupgrade 直接刷），但刷 NOWIFI 后无线就没了，回退要重刷 WiFi 版。

---

## 六、自定义

- **加包**：运行时填 `extra_packages`，或写进 `config/base.config`（`CONFIG_PACKAGE_xxx=y`）。
- **只去掉某个第三方插件**：删 `base.config` 里对应两三行；全去掉就把 `enable_thirdparty` 设为 `no`。
- **加机型**：`config/base.config` 加 `CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_xxx=y`，再把 `_build.yml` 顶部 `DEVICES` 加上 `xxx`（打包按名字找文件，两处必须一致）。
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
| 编译 6 小时被杀 | 减少机型 / 关第三方插件 |
| 发 Release 403 | Workflow permissions 没给 Read and write |

---

## 八、说明

- NSS 驱动/固件、DDNSTO、集客 AC 都是**闭源二进制**，仅供个人自用。
- 工作流只编译，不改分区表、不加后门，产物 = 标准 LibWrt 镜像 + 上述插件。
- LibWrt 仓库 400MB+、kenzok8 feed 150MB+，首次 clone 慢属正常。
