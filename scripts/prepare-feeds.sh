#!/usr/bin/env bash
# 合并「公共配置 + 变体配置」生成 .config
#
# 用法: prepare-config.sh <base.config> <variant.config> <输出.config> [enable_thirdparty] [extra_packages]
# 例:   prepare-config.sh ../config/base.config ../config/nowifi.config .config yes "luci-app-wol"
#
# 为什么不能直接 cat：
#   OpenWrt 的 toplevel.mk 在 prepare-tmpinfo 阶段会把 .config 当 makefile include 进来，
#   于是 .config 里任何一行都会被 GNU make 解析。带中文/全角符号的注释、BOM、CR、零宽字符
#   都可能让 make 报 “empty variable name” 之类的错（哪怕内容看起来完全正常）。
#   所以这里只输出 kconfig 真正需要的两种行：
#       CONFIG_xxx=...
#       # CONFIG_xxx is not set
#   注释留在 config/*.config 里给人看就够了，不进 .config。
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
if [ ! -f "$VARIANT_CONF" ] || [ ! -s "$VARIANT_CONF" ]; then
  echo "::error::缺少或空的变体配置 $VARIANT_CONF"
  exit 1
fi
RAW="$(mktemp)"
# 1) 先拼起来（保留注释，后面统一过滤）
{
  cat "$BASE"
  printf '\n\n'
  cat "$VARIANT_CONF"
} > "$RAW"
# 2) 去掉 BOM 和 CR（Windows 上另存/粘贴过的文件常带这两个）
sed -i -e '1s/^\xEF\xBB\xBF//' -e 's/\r$//' "$RAW"
# 3) 关掉第三方插件时，先按注释标记删掉整段（必须在过滤注释之前做）
if [ "$ENABLE_THIRD_PARTY" != "yes" ]; then
  sed -i '/# >>> THIRD-PARTY-BEGIN/,/# <<< THIRD-PARTY-END/d' "$RAW"
  echo "已剔除第三方插件配置段"
fi
# 4) 只保留 kconfig 认的行
#    注意键名里会有连字符（kmod-qca-nss-drv、luci-app-store、miniupnpd-nftables），
#    字符类必须含 '-'，否则这些行会被误删。
grep -E '^(CONFIG_[A-Za-z0-9_.-]+=|# CONFIG_[A-Za-z0-9_.-]+ is not set)' "$RAW" > "$OUT" || true
# 5) 记录真正可疑的行（既不是注释/空行，也不是合法赋值），方便排查
SUSPICIOUS="$(grep -nvE '^([[:space:]]*#|[[:space:]]*$|CONFIG_[A-Za-z0-9_.-]+=.*)$' "$RAW" | head -5 || true)"
if [ -n "$SUSPICIOUS" ]; then
  echo "::warning::config 里有非标准行（已丢弃，下面是前几条）："
  echo "$SUSPICIOUS"
fi
for pkg in $EXTRA_PACKAGES; do
  echo "CONFIG_PACKAGE_${pkg}=y" >> "$OUT"
done
# 6) 基本体检：太少说明 base/variant 没读到
LINES="$(wc -l < "$OUT" | tr -d ' ')"
if [ "$LINES" -lt 20 ]; then
  echo "::error::生成的 .config 只有 $LINES 行，明显不对（base/variant 没读到？）"
  echo "--- .config 全文 ---"
  cat "$OUT"
  rm -f "$RAW"
  exit 1
fi
echo "已生成 $OUT"
echo "  变体: $(basename "$VARIANT_CONF")"
echo "  第三方插件: $ENABLE_THIRD_PARTY"
echo "  额外包: ${EXTRA_PACKAGES:-（无）}"
echo "  有效行数: $LINES"
echo "  前三行:"
head -3 "$OUT" | sed 's/^/    /'
rm -f "$RAW"
