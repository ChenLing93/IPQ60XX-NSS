#!/usr/bin/env bash
# 合并「公共配置 + 变体配置」生成 .config
#
# 用法: prepare-config.sh <base.config> <variant.config> <输出.config> [enable_thirdparty] [extra_packages]
# 例:   prepare-config.sh ../config/base.config ../config/nowifi.config .config yes "luci-app-wol"
#
# 说明：在 openwrt/ 目录下执行；变体配置追加在后面，所以它的行优先。
set -euo pipefail

BASE="${1:?用法: prepare-config.sh <base.config> <variant.config> <输出.config> [enable_thirdparty] [extra_packages]}"
VARIANT_CONF="${2:?缺少变体配置}"
OUT="${3:?缺少输出文件}"
ENABLE_THIRD_PARTY="${4:-yes}"
EXTRA_PACKAGES="${5:-}"

if [ ! -f "$BASE" ]; then
  echo "::error::找不到公共配置 $BASE"
  exit 1
fi

cat "$BASE" > "$OUT"

if [ -f "$VARIANT_CONF" ] && [ -s "$VARIANT_CONF" ]; then
  printf '\n# ===== 变体追加: %s =====\n' "$(basename "$VARIANT_CONF")" >> "$OUT"
  cat "$VARIANT_CONF" >> "$OUT"
else
  echo "::error::缺少变体配置 $VARIANT_CONF"
  exit 1
fi

# 关掉第三方插件：把 base.config 里标记的那一段整段删掉
if [ "$ENABLE_THIRD_PARTY" != "yes" ]; then
  sed -i '/# >>> THIRD-PARTY-BEGIN/,/# <<< THIRD-PARTY-END/d' "$OUT"
  echo "已剔除第三方插件配置段"
fi

for pkg in $EXTRA_PACKAGES; do
  echo "CONFIG_PACKAGE_${pkg}=y" >> "$OUT"
done

echo "已生成 $OUT"
echo "  变体: $(basename "$VARIANT_CONF")"
echo "  第三方插件: $ENABLE_THIRD_PARTY"
echo "  额外包: ${EXTRA_PACKAGES:-（无）}"
