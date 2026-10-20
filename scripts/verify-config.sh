#!/usr/bin/env bash
# @id: verify-config.sh
# 在 make defconfig 之后校验配置：机型、公共包、USB/LED、第三方插件、变体一致性
#
# 用法: verify-config.sh <wifi|nowifi> [enable_thirdparty] [strict_thirdparty]
# 说明：在 openwrt/ 目录下执行，读 ./.config
#
# 策略：
#   机型 / NSS / UPnP / USB / LED 缺失 -> 硬失败（固件不可用）
#   第三方插件缺失                    -> strict_thirdparty=yes 时硬失败，
#                                        否则只告警 + 打印诊断
#   注意这里全部是在 defconfig 之后、开编之前判的，失败的成本是几秒而不是 3 小时。
set -euo pipefail

VARIANT="${1:?用法: verify-config.sh <wifi|nowifi> [enable_thirdparty] [strict_thirdparty]}"
ENABLE_THIRD_PARTY="${2:-yes}"
STRICT_THIRD_PARTY="${3:-yes}"
ENABLE_DOCKER="${4:-no}"
DEVICES="${DEVICES:-redmi_ax5 zn_m2 link_nn6000-v2}"

CONFIG_FILE=".config"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "::error::找不到 .config"
  exit 1
fi

fail=0
missing=""
warn_missing=""
not_pulled=""

has() { grep -qx "CONFIG_PACKAGE_$1=y" "$CONFIG_FILE"; }
in_meta() { grep -qx "config PACKAGE_$1" tmp/.config-package.in 2>/dev/null; }
# 源码目录在不在（feed 里的是符号链接，所以用 compgen 而不是 [ -d ]）
src_exists() {
  compgen -G "package/feeds/*/$1" >/dev/null 2>&1 \
    || compgen -G "package/$1" >/dev/null 2>&1 \
    || compgen -G "package/*/$1" >/dev/null 2>&1 \
    || compgen -G "package/*/*/$1" >/dev/null 2>&1
}

# 某个包没被选中时，把原因摊开：目录在不在、kconfig 符号在不在、依赖是什么
diagnose_pkg() {
  local p="$1" dirs
  echo "---- 诊断：$p ----"

  dirs="$(ls -d package/feeds/*/"$p" 2>/dev/null || true)"
  if [ -z "$dirs" ]; then
    dirs="$(ls -d package/"$p" package/*/"$p" package/*/*/"$p" 2>/dev/null || true)"
  fi
  if [ -z "$dirs" ]; then
    echo "  [x] 找不到源码目录 → feed 没把它装进来 / clone 失败（包名不对，或该 feed 里没有）"
  else
    echo "  [ok] 源码目录: $(echo "$dirs" | tr '\n' ' ')"
  fi

  if [ -f tmp/.config-package.in ]; then
    if in_meta "$p"; then
      echo "  [ok] kconfig 符号存在，相关依赖："
      awk -v pat="config PACKAGE_${p}\$" '
        $0 ~ pat { f = 1; next }
        f && /^config / { f = 0 }
        f && /(depends on|select|default)/ { print "       " $0 }
      ' tmp/.config-package.in | head -12
      echo "  → 符号在却没被选中，通常是上面某个 depends on 的条件没满足（缺 kmod / 缺运行库）"
    else
      echo "  [x] tmp/.config-package.in 里没有该符号 → 包没进入构建元数据（dump 失败或源码没拉到）"
    fi
  else
    echo "  [?] 没有 tmp/.config-package.in（defconfig 没生成？）"
  fi

  echo "  .config 中与该包有关的行："
  grep -E "PACKAGE_${p}(=|[[:space:]])" "$CONFIG_FILE" | head -5 || true
}

echo "========== 机型 =========="
for dev in $DEVICES; do
  if grep -qx "CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_${dev}=y" "$CONFIG_FILE"; then
    echo "  [OK] $dev"
  else
    echo "  [缺失] $dev"
    fail=1
  fi
done
if [ "$fail" -ne 0 ]; then
  echo "::error::当前源码分支不包含上面列出的机型，该分支支持："
  grep -oE 'Device/[a-z0-9._-]+' target/linux/qualcommax/image/ipq60xx.mk | sed 's#Device/#  #' | sort -u || true
  exit 1
fi

echo "========== 公共包 =========="
for p in kmod-qca-nss-drv kmod-qca-nss-ecm kmod-qca-nss-dp kmod-nss-ifb \
         luci-app-upnp miniupnpd-nftables; do
  if has "$p"; then
    echo "  [OK] $p"
  else
    echo "  [缺失] $p"
    missing="$missing $p"
  fi
done

echo "========== USB / 外接存储 =========="
for p in kmod-usb-storage kmod-usb-storage-uas kmod-fs-vfat kmod-fs-exfat \
         kmod-fs-ntfs3 kmod-nls-utf8 block-mount usbutils; do
  if has "$p"; then
    echo "  [OK] $p"
  else
    echo "  [缺失] $p"
    missing="$missing $p"
  fi
done
# 这些属于「有更好」：缺了只提示，不挡编译
for p in kmod-usb-storage-extras kmod-fs-ext4 kmod-fs-btrfs kmod-usb-serial \
         kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-hid; do
  has "$p" || echo "  [提示] $p 没选中（非必需）"
done

echo "========== LED =========="
for p in kmod-ledtrig-netdev kmod-ledtrig-timer kmod-usb-ledtrig-usbport; do
  if has "$p"; then
    echo "  [OK] $p"
  else
    echo "  [缺失] $p"
    missing="$missing $p"
  fi
done

echo "========== 家用常用插件 =========="
for p in luci-app-nlbwmon ; do
  if has "$p"; then
    echo "  [OK] $p"
  else
    echo "  [缺失] $p"
    missing="$missing $p"
  fi
done

if [ "$ENABLE_THIRD_PARTY" = "yes" ]; then
  echo "========== 第三方插件 =========="
  for p in luci-app-store luci-lib-taskd luci-lib-xterm taskd \
           luci-app-diskman luci-app-partexp luci-app-homeproxy sing-box luci-app-autoreboot \
           ddnsto luci-app-ddnsto luci-app-wechatpush \
           gecoosac luci-app-gecoosac \
           luci-theme-aurora luci-app-aurora-config ; do
    if has "$p"; then
      echo "  [OK] $p"
    elif in_meta "$p"; then
      echo "  [缺失] $p —— 源码和元数据都在，但没被选中（依赖没满足？）"
      warn_missing="$warn_missing $p"
    elif src_exists "$p"; then
      echo "  [缺失] $p —— 源码在，但没进元数据（Makefile dump 失败？）"
      warn_missing="$warn_missing $p"
    else
      echo "  [缺失] $p —— 源码没拉到（feed/clone 失败）"
      warn_missing="$warn_missing $p"
      not_pulled="$not_pulled $p"
    fi
  done
else
  echo "========== 第三方插件：已跳过 =========="
fi

if [ "$ENABLE_DOCKER" = "yes" ]; then
  echo "========== Docker =========="
  for p in luci-app-dockerman luci-lib-docker dockerd containerd runc docker tini ; do
    if has "$p"; then
      echo "  [OK] $p"
    elif in_meta "$p"; then
      echo "  [缺失] $p —— 源码和元数据都在，但没被选中（依赖没满足？）"
      warn_missing="$warn_missing $p"
    elif src_exists "$p"; then
      echo "  [缺失] $p —— 源码在，但没进元数据（dump 失败？）"
      warn_missing="$warn_missing $p"
    else
      echo "  [缺失] $p —— 源码没拉到"
      warn_missing="$warn_missing $p"
      not_pulled="$not_pulled $p"
    fi
  done
  echo "  [!] 提醒：dockerd+containerd+runc+docker 解压后约 60MB，AX5 / ZN-M2 是 128MB flash，"
  echo "      和 sing-box / 集客 AC 一起很可能放不下，编完注意看产物大小。"
else
  echo "========== Docker：已关闭（enable_docker=$ENABLE_DOCKER）=========="
fi

echo "========== 变体：$VARIANT =========="
case "$VARIANT" in
  wifi)
    for p in kmod-ath11k kmod-ath11k-ahb; do
      if has "$p"; then
        echo "  [OK] $p"
      else
        echo "  [缺失] $p"
        missing="$missing $p"
      fi
    done
    if grep -qE '^CONFIG_PACKAGE_wpad[a-z0-9-]*=y$' "$CONFIG_FILE"; then
      echo "  [OK] wpad"
    else
      echo "  [缺失] wpad"
      missing="$missing wpad"
    fi
    ;;
  nowifi)
    bad="$(grep -E '^CONFIG_PACKAGE_(kmod-ath11k[a-z0-9-]*|wpad[a-z0-9-]*|hostapd[a-z0-9-]*)=y$' "$CONFIG_FILE" || true)"
    if [ -n "$bad" ]; then
      echo "::error::NOWIFI 版本里仍然启用了无线组件："
      echo "$bad"
      fail=1
    else
      echo "  [OK] 没有 ath11k / wpad / hostapd"
    fi
    if grep -q '^CONFIG_TARGET_PER_DEVICE_ROOTFS=y$' "$CONFIG_FILE"; then
      echo "  [!] TARGET_PER_DEVICE_ROOTFS=y 时，机型默认包会被 select 强制打开，"
      echo "      NOWIFI 关无线的做法（.config 里 not set）会失效 —— 见 README 第四节"
    fi
    ;;
  *)
    echo "::error::未知变体 '$VARIANT'（只支持 wifi / nowifi）"
    exit 1
    ;;
esac

echo "========== NSS / 无线选项 =========="
grep -E '^CONFIG_(NSS_FIRMWARE_VERSION|ATH11K_MEM_PROFILE|SING_BOX_BUILD)[A-Z0-9_]*=' "$CONFIG_FILE" || true

# 第三方插件缺失：先诊断，再按 strict_thirdparty 决定是告警还是硬失败
if [ -n "$warn_missing" ]; then
  echo ""
  echo "========== 第三方插件缺失诊断 =========="
  for p in $warn_missing; do
    diagnose_pkg "$p"
  done
  if [ -n "$not_pulled" ]; then
    echo ""
    echo "以下插件是「源码没拉到」，基本就是 feed/clone 那一步的网络问题：$not_pulled"
  fi
  if [ "$STRICT_THIRD_PARTY" = "yes" ]; then
    echo "::error::以下插件没有进固件：$warn_missing"
    echo "  （strict_thirdparty=yes，现在停在这里，省掉 2~3 小时的无效编译）"
    echo "  想「编不过也出固件」，把工作流的 strict_thirdparty 设为 no，或先把 enable_thirdparty 设为 no。"
    exit 1
  fi
  echo "::warning::以下插件没有被选中：$warn_missing —— 固件会照常编译，但里面没有它们"
fi

if [ -n "$missing" ]; then
  echo "::error::以下关键包没有被选中：$missing"
  for p in $missing; do
    diagnose_pkg "$p" || true
  done
  exit 1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "配置校验通过（变体 $VARIANT）"
