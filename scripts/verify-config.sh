#!/usr/bin/env bash
# 在 make defconfig 之后校验配置：机型、公共包、第三方插件、变体一致性
#
# 用法: verify-config.sh <wifi|nowifi> [enable_thirdparty]
# 说明：在 openwrt/ 目录下执行，读 ./.config
set -euo pipefail

VARIANT="${1:?用法: verify-config.sh <wifi|nowifi> [enable_thirdparty]}"
ENABLE_THIRD_PARTY="${2:-yes}"
DEVICES="${DEVICES:-redmi_ax5 zn_m2 link_nn6000-v2}"

CONFIG_FILE=".config"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "::error::找不到 .config"
  exit 1
fi

fail=0
missing=""

has() { grep -qx "CONFIG_PACKAGE_$1=y" "$CONFIG_FILE"; }

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

if [ "$ENABLE_THIRD_PARTY" = "yes" ]; then
  echo "========== 第三方插件 =========="
  for p in luci-app-store luci-lib-taskd ddnsto luci-app-ddnsto \
           luci-app-wechatpush gecoosac luci-app-gecoosac; do
    if has "$p"; then
      echo "  [OK] $p"
    else
      echo "  [缺失] $p"
      missing="$missing $p"
    fi
  done
else
  echo "========== 第三方插件：已跳过 =========="
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
    # 无无线版本：ath11k / wpad / hostapd 一个都不许有
    bad="$(grep -E '^CONFIG_PACKAGE_(kmod-ath11k[a-z0-9-]*|wpad[a-z0-9-]*|hostapd[a-z0-9-]*)=y$' "$CONFIG_FILE" || true)"
    if [ -n "$bad" ]; then
      echo "::error::NOWIFI 版本里仍然启用了无线组件："
      echo "$bad"
      fail=1
    else
      echo "  [OK] 没有 ath11k / wpad / hostapd"
    fi
    ;;
  *)
    echo "::error::未知变体 '$VARIANT'（只支持 wifi / nowifi）"
    exit 1
    ;;
esac

echo "========== NSS / 无线选项 =========="
grep -E '^CONFIG_(NSS_FIRMWARE_VERSION|ATH11K_MEM_PROFILE)[A-Z0-9_]*=' "$CONFIG_FILE" || true

if [ -n "$missing" ]; then
  echo "::error::以下软件包没有被选中：$missing"
  echo "可能原因：feeds 没拉到 / 包名变化 / 依赖缺失。当前 feeds 里的候选："
  ./scripts/feeds list -n 2>/dev/null \
    | grep -E '^(luci-app-store|luci-app-ddnsto|ddnsto|luci-app-wechatpush|gecoosac|luci-app-gecoosac|luci-app-upnp|miniupnpd[^ ]*)$' || true
  echo "只想先出个可用固件：把 enable_thirdparty 设为 no 再跑一次。"
  exit 1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "配置校验通过（变体 $VARIANT）"
