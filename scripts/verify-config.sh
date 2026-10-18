#!/usr/bin/env bash
# 在 make defconfig 之后校验配置：机型、公共包、第三方插件、变体一致性
#
# 用法: verify-config.sh <wifi|nowifi> [enable_thirdparty]
# 说明：在 openwrt/ 目录下执行，读 ./.config
#
# 策略：
#   机型 / NSS / UPnP 缺失  -> 硬失败（固件不可用）
#   第三方插件缺失          -> 只告警 + 自动打印诊断（不阻断 3 小时的编译）
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
warn_missing=""

has() { grep -qx "CONFIG_PACKAGE_$1=y" "$CONFIG_FILE"; }

# 某个包没被选中时，把原因摊开：目录在不在、kconfig 符号在不在、依赖是什么
diagnose_pkg() {
  local p="$1" dirs sym
  echo "---- 诊断：$p ----"

  dirs="$(ls -d package/feeds/*/"$p" 2>/dev/null || true)"
  if [ -z "$dirs" ]; then
    echo "  [x] package/feeds/*/$p 不存在 → feeds 没把它装进来（包名不对或该 feed 里没有）"
  else
    echo "  [ok] 源码目录: $(echo "$dirs" | tr '\n' ' ')"
  fi

  if [ -f tmp/.config-package.in ]; then
    if grep -qx "config PACKAGE_${p}" tmp/.config-package.in; then
      echo "  [ok] kconfig 符号存在，相关依赖："
      awk -v pat="config PACKAGE_${p}\$" '
        $0 ~ pat { f = 1; next }
        f && /^config / { f = 0 }
        f && /(depends on|select|default)/ { print "       " $0 }
      ' tmp/.config-package.in | head -12
    else
      echo "  [x] tmp/.config-package.in 里没有该符号 → 包没进入构建元数据"
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

if [ "$ENABLE_THIRD_PARTY" = "yes" ]; then
  echo "========== 第三方插件 =========="
  for p in luci-app-store luci-lib-taskd ddnsto luci-app-ddnsto \
           luci-app-wechatpush gecoosac luci-app-gecoosac; do
    if has "$p"; then
      echo "  [OK] $p"
    else
      echo "  [缺失] $p"
      warn_missing="$warn_missing $p"
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

# 第三方插件缺失：先告警 + 诊断，不阻断编译
if [ -n "$warn_missing" ]; then
  echo ""
  echo "========== 第三方插件缺失诊断 =========="
  for p in $warn_missing; do
    diagnose_pkg "$p"
  done
  echo "::warning::以下第三方插件没有被选中：$warn_missing —— 固件会照常编译，但里面没有它们"
  echo "（想强制要求它们全都在，请自行把它们从告警改成硬失败，或先把 enable_thirdparty 设为 no）"
fi

# 公共包 / 变体包缺失：硬失败
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
