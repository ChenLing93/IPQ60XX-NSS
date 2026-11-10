#!/usr/bin/env bash
# 修 NN6000 v1/v2 设备树里的按键冲突。
#
# 问题（6.18 实测）：
#   ipq6018-pinctrl: pin GPIO_42 already requested by 78b7000.i2c
#   gpio-keys keys: probe with driver gpio-keys failed with error -22
#
# 原因：ipq6000-link.dtsi 的 keys 节点把 GPIO42 给了 WPS 键，
#       而同一棵树里 i2c_1_pins 也占了 GPIO42/43。
#       gpio-keys 是一个整体节点，probe 失败后 **reset 键（GPIO9）也用不了**。
#
# 处理：删掉 wps 那个子节点，只留 reset。
#
# 用法: patch-dts-keys.sh <dts目录>
set -euo pipefail

DTS_DIR="${1:?用法: patch-dts-keys.sh <dts目录>}"
if [ ! -d "$DTS_DIR" ]; then
  echo "::error::找不到 dts 目录：$DTS_DIR"
  exit 1
fi

fixed=0
for f in "$DTS_DIR"/ipq6000-link.dtsi "$DTS_DIR"/ipq6000-nn6000-v*.dts; do
  [ -f "$f" ] || continue
  if ! grep -q 'KEY_WPS_BUTTON' "$f"; then
    continue
  fi

  # 删掉 wps { ... }; 这个块（里面没有嵌套花括号）
  awk '
    /^[[:space:]]*wps \{[[:space:]]*$/ { skip = 1 }
    skip && /^[[:space:]]*\};[[:space:]]*$/ { skip = 0; next }
    !skip { print }
  ' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"

  # 确认 reset 还在
  if grep -q 'KEY_RESTART' "$f"; then
    echo "  [fix] $(basename "$f")：已删除 wps 键（GPIO42 冲突），reset 保留"
  else
    echo "::warning::$(basename "$f") 删掉 wps 后没找到 reset 键，检查一下！"
  fi
  fixed=$((fixed + 1))
done

echo "已处理 $fixed 个 dts"
