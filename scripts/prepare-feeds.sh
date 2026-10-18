#!/usr/bin/env bash
# 拉取官方 feeds，并按需追加第三方 feeds + 只安装需要的插件包
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
./scripts/feeds update kenzo gecoo wechat

echo "===== 安装插件包 ====="
# 只装这几个，避免把 kenzok8 整个 feed 的 300+ 包都挂进来
./scripts/feeds install \
  luci-app-store luci-lib-taskd \
  ddnsto luci-app-ddnsto \
  luci-app-wechatpush \
  gecoosac luci-app-gecoosac
