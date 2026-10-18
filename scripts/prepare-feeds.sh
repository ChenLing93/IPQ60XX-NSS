#!/usr/bin/env bash
# 拉取官方 feeds，并按需追加第三方 feeds + 安装需要的插件包
#
# 用法: prepare-feeds.sh <feeds.extra.conf> [enable_thirdparty]
# 说明：在 openwrt/ 目录下执行
set -euo pipefail
EXTRA_FEEDS="${1:?用法: prepare-feeds.sh <feeds.extra.conf> [enable_thirdparty]}"
ENABLE_THIRD_PARTY="${2:-yes}"
# 相对路径转绝对，避免后面路径混乱
case "$EXTRA_FEEDS" in
  /*) ;;
  *) EXTRA_FEEDS="$(pwd)/$EXTRA_FEEDS" ;;
esac
[ -f feeds.conf ] || cp feeds.conf.default feeds.conf
echo "===== 官方 feeds ====="
./scripts/feeds update -a || ./scripts/feeds update -a
./scripts/feeds install -a
if [ "$ENABLE_THIRD_PARTY" != "yes" ]; then
  echo "===== 跳过第三方 feeds（enable_thirdparty=no）====="
  exit 0
fi
if [ ! -f "$EXTRA_FEEDS" ]; then
  echo "::error::缺少第三方 feed 清单 $EXTRA_FEEDS"
  exit 1
fi
echo "===== 追加第三方 feeds ====="
while IFS= read -r line; do
  case "$line" in
    ''|'#'*) continue ;;
  esac
  if grep -qxF "$line" feeds.conf; then
    echo "  已存在: $line"
  else
    echo "  + $line"
    echo "$line" >> feeds.conf
  fi
done < "$EXTRA_FEEDS"
echo "===== 拉取第三方 feeds ====="
./scripts/feeds update istore kenzo gecoo wechat
echo "===== 安装插件包 ====="
# 逐个装：某个包名不存在时不至于把整步带崩，最后统一告警；
# 真正的判定交给 verify-config.sh（看 .config 里有没有 =y）
failed=""
for pkg in \
    luci-app-store luci-lib-taskd \
    ddnsto luci-app-ddnsto \
    luci-app-wechatpush \
    gecoosac luci-app-gecoosac ; do
  if ./scripts/feeds install "$pkg" >/dev/null 2>&1; then
    echo "  [ok] $pkg"
  else
    echo "  [!]  $pkg 安装失败（可能包名变了）"
    failed="$failed $pkg"
  fi
done
if [ -n "$failed" ]; then
  echo "::warning::以下包 feeds install 失败：$failed —— 下一步会给出具体诊断"
fi
# ----- Aurora 主题：仓库根目录就是包本体，不能当 feed 用 -----
# 当 feed 用时目录名会变成 feeds/<feed名>，而 luci.mk 的 LUCI_NAME 取的是目录名，
# 包名会算成 "<feed名>" 而不是 luci-theme-aurora，菜单分类也会错。
# 所以按上游 README 的做法：直接 clone 到 package/luci-theme-aurora。
echo "===== Aurora 主题 ====="
THEME_REPO="https://github.com/ChenLing93/luci-theme-aurora.git"
THEME_DIR="package/luci-theme-aurora"
if [ -d "$THEME_DIR" ]; then
  echo "  已存在: $THEME_DIR"
elif git clone --depth 1 "$THEME_REPO" "$THEME_DIR"; then
  echo "  [ok] 已克隆到 $THEME_DIR"
else
  echo "::warning::Aurora 主题 clone 失败，本次固件不带主题（不影响 NSS 和其它插件）"
fi
