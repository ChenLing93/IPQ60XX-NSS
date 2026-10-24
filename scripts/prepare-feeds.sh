#!/usr/bin/env bash
# @id: prepare-feeds.sh
# 拉取官方 feeds，并按需追加第三方 feeds + 安装需要的插件包
#
# 用法: prepare-feeds.sh <feeds.extra.conf> [enable_thirdparty]
# 说明：在 openwrt/ 目录下执行
set -euo pipefail
if [ "$#" -lt 1 ]; then
  echo "::error::prepare-feeds.sh 需要 1~2 个参数，实际收到 $# 个"
  echo "  用法: prepare-feeds.sh <feeds.extra.conf> [enable_thirdparty]"
  echo "  工作流里的正确调用: prepare-feeds.sh <仓库绝对路径>/config/feeds.extra.conf <yes|no>"
  exit 1
fi
EXTRA_FEEDS="${1:?用法: prepare-feeds.sh <feeds.extra.conf> [enable_thirdparty]}"
ENABLE_THIRD_PARTY="${2:-yes}"
ENABLE_DOCKER="${3:-no}"
# 相对路径转绝对，避免后面路径混乱
case "$EXTRA_FEEDS" in
  /*) ;;
  *) EXTRA_FEEDS="$(pwd)/$EXTRA_FEEDS" ;;
esac
[ -f feeds.conf ] || cp feeds.conf.default feeds.conf

# 主树 feeds 用的分支（例如 openwrt-25.12）。后面 sparse clone 要跟它保持一致：
# 不指定分支就会拿 immortalwrt 的默认分支（master），那里的 homeproxy / sing-box
# 可能已经是给更新内核和更新 LuCI 写的版本，跟这棵树对不上。
FEED_BRANCH="$(awk -F';' '/^src-git packages /{print $2; exit}' feeds.conf.default 2>/dev/null | tr -d '[:space:]' || true)"
if [ -z "${FEED_BRANCH:-}" ]; then
  FEED_BRANCH="openwrt-25.12"
  echo "  [!] 没能从 feeds.conf.default 解析出分支，sparse clone 用 $FEED_BRANCH"
else
  echo "  sparse clone 分支: $FEED_BRANCH"
fi

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
# 要 update 哪些 feed：从清单文件里解析，而不是写死 istore kenzo gecoo wechat。
# 写死的后果——在 feeds.extra.conf 里加一个新 feed 永远不会被拉；删掉/改名一个，
# 这个 ./scripts/feeds update 会报未知 feed，加上 set -e 直接把这步带崩。
third_feeds="$(grep -vE '^[[:space:]]*(#|$)' "$EXTRA_FEEDS" | awk '{print $2}' | tr '\n' ' ' || true)"
echo "===== 拉取第三方 feeds: $third_feeds ====="
# shellcheck disable=SC2086
./scripts/feeds update $third_feeds
echo "===== iStore 的运行时依赖 ====="
# iStore 的界面本体不走 feed（见下面「从仓库取包」一节），三个运行时依赖从 feed 装最省事。
# 注意两点：
#   1) 不要带 -d y —— 那是给「已有 .config」改默认值用的，这里 .config 还没生成；
#   2) feeds install 找不到包时只打 WARNING、退出码仍是 0，所以必须按「目录在不在」判断，
#      否则会出现「日志 [ok]、实际没装」的假成功（iStore 以前就这么骗过人）。
try_istore_deps() {
  local feed="$1" n=0 d
  ./scripts/feeds install -p "$feed" luci-lib-taskd luci-lib-xterm taskd \
    > /tmp/istore-install.log 2>&1 || true
  for d in luci-lib-taskd luci-lib-xterm taskd ; do
    compgen -G "package/feeds/*/$d" >/dev/null 2>&1 && n=$((n + 1))
  done
  [ "$n" -eq 3 ]
}
istore_ok=0
if try_istore_deps istore ; then
  istore_ok=1
  echo "  [ok] luci-lib-taskd / luci-lib-xterm / taskd（feed: istore，已按目录确认）"
else
  echo "  [!]  istore feed 没装全（日志：/tmp/istore-install.log），回退到 kenzo feed"
  tail -20 /tmp/istore-install.log | sed 's/^/       /' || true
  if try_istore_deps kenzo ; then
    istore_ok=1
    echo "  [ok] luci-lib-taskd / luci-lib-xterm / taskd（feed: kenzo，已按目录确认）"
  else
    echo "  [!]  kenzo feed 也没装全"
    tail -20 /tmp/istore-install.log | sed 's/^/       /' || true
  fi
fi
if [ "$istore_ok" -eq 0 ]; then
  echo "::warning::iStore 的依赖没装成功，固件里 iStore 大概率打不开（原因见上面日志）"
fi
echo "===== 安装其余第三方包 ====="
failed=""
# 逐个装，某个失败不至于把整步带崩；不带 -p，让 feeds 按 feeds.conf 顺序找
for pkg in \
    ddnsto luci-app-ddnsto \
    luci-app-wechatpush \
    gecoosac luci-app-gecoosac \
    luci-app-diskman \
    luci-app-partexp ; do
  # 同样按目录判断，不信退出码（feeds 找不到包也是 0）
  if ./scripts/feeds install "$pkg" >/dev/null 2>&1 \
     && compgen -G "package/feeds/*/$pkg" >/dev/null 2>&1; then
    echo "  [ok] $pkg"
  else
    echo "  [!]  $pkg 安装失败或没落地（包名变了 / 该 feed 里没有）"
    failed="$failed $pkg"
  fi
done
# Docker：默认不开（enable_docker=no），打开了才装
if [ "$ENABLE_DOCKER" = "yes" ]; then
  echo "===== 安装 Docker 相关 ====="
  # luci-lib-docker 官方 luci feed 里没有，必须从 dockerlib feed 取
  if ./scripts/feeds install -p dockerlib luci-lib-docker >/dev/null 2>&1; then
    echo "  [ok] luci-lib-docker（feed: dockerlib）"
  else
    echo "  [!]  luci-lib-docker 安装失败 —— dockerman 依赖它，缺了就编不进去"
    failed="$failed luci-lib-docker"
  fi
  for pkg in luci-app-dockerman docker dockerd containerd runc tini cgroupfs-mount ; do
    if ./scripts/feeds install "$pkg" >/dev/null 2>&1; then
      echo "  [ok] $pkg"
    else
      echo "  [!]  $pkg 安装失败（官方 packages feed 里应该有，检查 feeds 是否完整）"
      failed="$failed $pkg"
    fi
  done
fi
if [ -n "$failed" ]; then
  echo "::warning::以下包 feeds install 失败：$failed —— 后面会给出具体诊断"
fi
# ----- 直接从仓库取包（这些仓库不是 feed 结构）-----
# 判据：Makefile 里用的是相对 include（../../luci.mk、../../lang/golang/golang-package.mk），
# 或者仓库根目录就是包本体。当 feed 用会算错包名，或者相对路径直接对不上。
echo "===== 从仓库取包：HomeProxy / 定时重启 / sing-box / Aurora ====="
clone_pkg() {
  repo="$1"; dir="$2"; name="$3"
  if [ -d "$dir" ]; then
    echo "  已存在: $dir"
  elif git clone --depth 1 "$repo" "$dir"; then
    echo "  [ok] $name 已克隆到 $dir"
  else
    echo "::warning::$name clone 失败，本次固件不含它（不影响 NSS 和其它插件）"
  fi
}
# 只取仓库里的某个子目录（immortalwrt/luci 有 200+ 个包，整仓 clone 又慢又占地方）
sparse_clone_pkg() {
  repo="$1"; srcpath="$2"; dir="$3"; name="$4"; branch="${5:-}"
  if [ -d "$dir" ]; then
    echo "  已存在: $dir"
    return 0
  fi
  tmp="$(mktemp -d)"
  clone_ok=0
  # 指定了分支就按分支浅克隆；分支不存在时自动退回默认分支，别让整个包拉不到
  if [ -n "$branch" ]; then
    if git clone --depth 1 --filter=blob:none --sparse --branch "$branch" \
         "$repo" "$tmp/repo" >/dev/null 2>&1; then
      clone_ok=1
    else
      echo "  [!] $name：分支 $branch 拉不到，退回默认分支（版本可能和主树不匹配）"
      rm -rf "$tmp/repo"
    fi
  fi
  if [ "$clone_ok" -eq 0 ]; then
    if git clone --depth 1 --filter=blob:none --sparse "$repo" "$tmp/repo" >/dev/null 2>&1; then
      clone_ok=1
    fi
  fi
  if [ "$clone_ok" -eq 1 ] \
     && git -C "$tmp/repo" sparse-checkout set "$srcpath" >/dev/null 2>&1 \
     && [ -e "$tmp/repo/$srcpath/Makefile" ]; then
    mkdir -p "$(dirname "$dir")"
    cp -a "$tmp/repo/$srcpath" "$dir"
    echo "  [ok] $name -> $dir"
    rm -rf "$tmp"
    return 0
  fi
  echo "::warning::$name 拉取失败（$repo 的 $srcpath），本次固件不含它"
  rm -rf "$tmp"
  return 1
}
# scan.mk 会把 DUMP 失败的原因写到 logs/<扫描目录>/<包路径>/dump.txt，
# 但那个目录平时没人看，所以这里直接把末尾几行打出来。
dump_log() {
  p="$1"; found=0
  for f in logs/package/"$p"/dump.txt \
           logs/package/feeds/*/"$p"/dump.txt \
           logs/feeds/*/"$p"/dump.txt \
           logs/feeds/*/*/"$p"/dump.txt ; do
    if [ -f "$f" ]; then
      found=1
      echo "    --- DUMP 日志 $f（末尾 15 行）---"
      tail -15 "$f" | sed 's/^/       /' || true
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "    （没找到 dump.txt —— 说明压根没走到 DUMP，多半是 Makefile 里没有 build 签名）"
  fi
  return 0
}
# iStore 界面本体：官方 feed 里它在 luci/ 子目录，feeds install 之后是
# package/feeds/istore/luci-app-store 这种**符号链接**，这棵树上那样 dump 会失败
# （症状就是「源码在、元数据里没符号」）。改成取实体目录 package/luci-app-store，
# 它的 Makefile 用 include $(TOPDIR)/feeds/luci/luci.mk（绝对路径），放哪都能编。
if sparse_clone_pkg "https://github.com/istoreos/istore.git" \
                    "luci/luci-app-store" \
                    "package/luci-app-store" "iStore"; then
  echo "  [ok] iStore 用实体目录（package/luci-app-store）"
else
  echo "  [!]  克隆失败，退回用 feed 里的符号链接版本"
  ./scripts/feeds install -p istore luci-app-store >/dev/null 2>&1 \
    || ./scripts/feeds install -p kenzo luci-app-store >/dev/null 2>&1 \
    || echo "::warning::iStore 兜底也失败，这次固件里不会有 iStore"
fi
# HomeProxy（sing-box 的 LuCI 前端）与 定时重启：都在 immortalwrt/luci 的 applications/ 下
sparse_clone_pkg "https://github.com/immortalwrt/luci.git" \
                 "applications/luci-app-homeproxy" \
                 "package/iluci/applications/luci-app-homeproxy" "HomeProxy" "$FEED_BRANCH"
sparse_clone_pkg "https://github.com/immortalwrt/luci.git" \
                 "applications/luci-app-autoreboot" \
                 "package/iluci/applications/luci-app-autoreboot" "定时重启" "$FEED_BRANCH"
# 这两个包都写 include ../../luci.mk。放在 package/iluci/applications/<包>/ 下,
# ../../ 正好是 package/iluci/，所以把本棵树自己的 feeds/luci/luci.mk 复制过去。
# 用本树的 luci.mk（而不是 immortalwrt 的），LuCI 主体版本才对得上。
if [ -d package/iluci ]; then
  if [ -f feeds/luci/luci.mk ]; then
    cp feeds/luci/luci.mk package/iluci/luci.mk
    echo "  [ok] 已放置 package/iluci/luci.mk（供 ../../luci.mk 使用）"
  else
    echo "::warning::找不到 feeds/luci/luci.mk，HomeProxy/定时重启 会因 include 失败而编不进去"
  fi
fi
# sing-box：immortalwrt/packages 的 net/sing-box，HomeProxy 的运行时依赖
sparse_clone_pkg "https://github.com/immortalwrt/packages.git" \
                 "net/sing-box" \
                 "package/sing-box" "sing-box" "$FEED_BRANCH"
if [ -f package/sing-box/Makefile ]; then
  # 它假设自己在 feeds/packages/net/sing-box 下，写的是相对 include，
  # 放到 package/sing-box 就指到别处去了，改成绝对路径。
  sed -i 's#include ../../lang/golang/golang-package.mk#include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#' \
    package/sing-box/Makefile
  if grep -q 'feeds/packages/lang/golang/golang-package.mk' package/sing-box/Makefile; then
    echo "  [ok] sing-box Makefile 的 golang 路径已改写"
  else
    echo "::warning::sing-box Makefile 改写没生效，golang-package.mk 可能找不到"
  fi
fi
# Aurora 主题 + 设置插件：仓库根目录就是包本体
clone_pkg "https://github.com/ChenLing93/luci-theme-aurora.git" \
          "package/luci-theme-aurora" "Aurora 主题"
clone_pkg "https://github.com/eamonxg/luci-app-aurora-config.git" \
          "package/luci-app-aurora-config" "Aurora 设置插件"
# ----- 修正「字母开头的版本号」-----
# 25.12 用的是 apk，apk 的版本号语法不允许以字母开头：
#   PKG_VERSION:=v0.3.4  →  --info "version:v0.3.4-r1"
#   ERROR: info field 'version' has invalid value: package version is invalid
# luci-lib-docker 就是这种写法（它的上游一直这么写，opkg 能忍、apk 不行）。
#
# 只处理「没有 PKG_SOURCE」的包（luci 库/主题这类纯脚本包），因为这类包的
# PKG_SOURCE_URL 通常不会拿 PKG_VERSION 拼下载地址；有 PKG_SOURCE 的包跳过，
# 避免把版本号改了导致下载 404。
echo "===== 修正字母开头的 PKG_VERSION（apk 不接受）====="
fixed=0
for mk in package/feeds/*/*/Makefile package/*/*/Makefile package/*/*/*/Makefile; do
  [ -f "$mk" ] || continue
  grep -q '^PKG_VERSION:=v' "$mk" 2>/dev/null || continue
  grep -q '^PKG_SOURCE' "$mk" 2>/dev/null && continue
  real="$(readlink -f "$mk" 2>/dev/null || echo "$mk")"
  sed -i 's/^PKG_VERSION:=v/PKG_VERSION:=/' "$real"
  echo "  [fix] ${real#"$PWD"/}：PKG_VERSION 去掉前导 v"
  fixed=$((fixed + 1))
done
if [ "$fixed" -eq 0 ]; then
  echo "  没有需要修正的包"
fi
# ----- 补 build 签名（放在所有包都到位之后）-----
# scan.mk 是这么发现包的：
#   find -L package -name Makefile | xargs grep -E 'call (BuildPackage|KernelPackage|...)'
# 命中的目录才会被 DUMP 成元数据；缺这行签名的包会被静默跳过。
echo "===== 检查 build 签名 ====="
for pkg in luci-app-store luci-lib-taskd luci-lib-xterm taskd ddnsto luci-app-ddnsto \
           luci-app-wechatpush gecoosac luci-app-gecoosac luci-theme-aurora \
           luci-app-aurora-config luci-app-diskman luci-app-partexp luci-app-nlbwmon \
           luci-app-homeproxy luci-app-autoreboot sing-box \
           luci-lib-docker luci-app-dockerman dockerd containerd runc ; do
  for d in package/feeds/*/"$pkg" package/"$pkg" package/*/"$pkg" package/*/*/"$pkg"; do
    [ -f "$d/Makefile" ] || continue
    if ! grep -qE 'call (Build/DefaultTargets|BuildPackage|KernelPackage)' "$d/Makefile"; then
      echo "  [fix] $d/Makefile 缺少 build 签名，补一行注释"
      printf '\n# call BuildPackage - OpenWrt buildroot signature\n' >> "$d/Makefile"
    fi
  done
done
echo "  签名检查完成"
# ----- 所有包就位后：强制重扫一次元数据 -----
echo "===== 强制重新扫描第三方包 ====="
# scan.mk 把「有哪些包目录」记在 tmp/info/.files-packageinfo.mk，并 -include 它。
# 这个文件如果是在当轮运行中才被重建，make 不会重读 —— 新装的包这一轮就等于不存在。
# 预先删掉它，make 会在读取阶段重建并自动 re-exec，新包就能被正确收进来。
# 只删这一个清单 + 派生结果，比整目录 rm -rf 更轻，也不会牵连其它缓存。
rm -f tmp/info/.files-packageinfo.mk \
      tmp/info/.files-packageinfo.stamp \
      tmp/.packageinfo \
      tmp/.config-package.in 2>/dev/null || true
echo "  已清理扫描清单缓存，开始重扫（完整输出：/tmp/tmpinfo.log）"
if make prepare-tmpinfo > /tmp/tmpinfo.log 2>&1; then
  echo "  重扫成功"
else
  echo "::error::prepare-tmpinfo 失败（元数据生成阶段出错）"
fi
echo "  --- 重扫日志末尾 ---"
tail -25 /tmp/tmpinfo.log | sed 's/^/       /' || true
# 没有 .config-package.in 时，下面逐个包判断毫无意义（全会是「未入库」）
if [ ! -s tmp/.config-package.in ]; then
  echo "  [x] tmp/.config-package.in 没生成 —— 上一步重扫失败了（原因见上面日志）"
  echo "::warning::元数据没生成，第三方包这轮无法入库；编译阶段的 defconfig 会再试一次"
else
  # ---- iStore 自愈：依赖里有本树不存在的包时，整包会永远选不上 ----
  # 典型例子：iStore 的 LUCI_DEPENDS 写死了 +libuci-lua +mount-utils，
  # 25.12 上这两个包要是改名/没了，PACKAGE_luci-app-store 就会被一个恒为 n 的
  # depends 卡住（现象：符号在，但 .config 里选不上）。这里把不存在的依赖剔掉再重扫一次。
  if ! grep -qx 'config PACKAGE_luci-app-store' tmp/.config-package.in 2>/dev/null \
     && [ -f package/luci-app-store/Makefile ]; then
    echo "  [!] iStore 还没入库，检查它依赖的包在本树里是否都存在"
    changed=0
    for dep in $(grep -E '^LUCI_DEPENDS' package/luci-app-store/Makefile | tail -1 \
                 | grep -oE '\+[A-Za-z0-9_.-]+' | tr -d '+'); do
      if ! grep -qx "config PACKAGE_${dep}" tmp/.config-package.in; then
        echo "      [fix] 本树没有 +$dep，从 LUCI_DEPENDS 里去掉"
        sed -i "s/+${dep}\b//g" package/luci-app-store/Makefile
        changed=1
      fi
    done
    if [ "$changed" -eq 1 ]; then
      echo "      改完重扫一次元数据…"
      rm -f tmp/info/.files-packageinfo.mk tmp/info/.files-packageinfo.stamp \
            tmp/.packageinfo tmp/.config-package.in 2>/dev/null || true
      if make prepare-tmpinfo > /tmp/tmpinfo-istore.log 2>&1; then
        echo "      重扫成功"
      else
        echo "::error::iStore 依赖修正后重扫失败"
        tail -20 /tmp/tmpinfo-istore.log | sed 's/^/       /' || true
      fi
    else
      echo "      依赖都存在于元数据里，所以不是依赖名的问题（看下面的 DUMP 日志）"
    fi
  fi
  echo "  元数据已生成，逐个确认（区分「源码没拉到」和「源码在但 Makefile 有问题」）："
  check_pkgs="luci-app-store luci-lib-taskd luci-lib-xterm taskd \
              luci-theme-aurora luci-app-aurora-config \
              luci-app-wechatpush luci-app-ddnsto gecoosac luci-app-gecoosac \
              luci-app-diskman luci-app-partexp luci-app-nlbwmon \
              luci-app-homeproxy sing-box luci-app-autoreboot"
  if [ "$ENABLE_DOCKER" = "yes" ]; then
    check_pkgs="$check_pkgs luci-lib-docker luci-app-dockerman dockerd containerd runc"
  fi
  for p in $check_pkgs ; do
    if grep -qx "config PACKAGE_${p}" tmp/.config-package.in 2>/dev/null; then
      echo "    [ok] $p 已入库"
    elif compgen -G "package/feeds/*/$p" >/dev/null \
      || compgen -G "package/$p" >/dev/null \
      || compgen -G "package/*/$p" >/dev/null \
      || compgen -G "package/*/*/$p" >/dev/null; then
      echo "    [x] $p 源码在，但没入库（Makefile dump 失败）"
      dump_log "$p"
    else
      echo "    [x] $p 源码没拉到（feed 里没这个包，或 clone 失败）"
    fi
  done
fi
# iStore 是历史上最容易「拉得到但编不进去」的一个，单独留一份取证
if ! grep -qx 'config PACKAGE_luci-app-store' tmp/.config-package.in 2>/dev/null; then
  echo "----- iStore 未入库，逐层取证 -----"
  echo "  1) find 能否发现它的 Makefile"
  { find -L package -maxdepth 6 -name Makefile 2>/dev/null | grep 'luci-app-store' | sed 's/^/       /' ; } || echo "       (find 没找到)"
  echo "  2) Makefile 里的 build 签名命中次数"
  { grep -cE 'call (Build/DefaultTargets|BuildPackage|KernelPackage)' \
      package/luci-app-store/Makefile package/feeds/*/luci-app-store/Makefile 2>/dev/null \
      | sed 's/^/       /' ; } || echo "       (读不到 Makefile)"
  echo "  3) FILELIST 里有没有它"
  { grep -h 'luci-app-store' tmp/info/.files-packageinfo-* 2>/dev/null | sed 's/^/       /' ; } || echo "       (FILELIST 里没有)"
  echo "  4) tmp/info 下的元数据片段（含隐藏文件）"
  { ls -1a tmp/info/ 2>/dev/null | grep -i 'istore\|store' | sed 's/^/       /' ; } || echo "       (没有 istore 片段)"
  echo "  5) DUMP 失败日志"
  dlog="$(find logs -path '*luci-app-store/dump.txt' 2>/dev/null | head -1 || true)"
  if [ -n "$dlog" ]; then
    tail -40 "$dlog" | sed 's/^/       /' || true
  else
    echo "       (没有 logs/.../luci-app-store/dump.txt → 没走到 DUMP)"
  fi
  echo "  6) 手动重跑 DUMP（带 TOPDIR，否则 \$(TOPDIR) 为空会报 /feeds/...）"
  store_dir="$(find -L package -maxdepth 6 -type d -name luci-app-store 2>/dev/null | head -1 || true)"
  if [ -n "$store_dir" ]; then
    { make -r DUMP=1 FEED=istore TOPDIR="$PWD" -C "$store_dir" 2>&1 | tail -30 | sed 's/^/       /' ; } || true
  fi
  echo "::warning::iStore 这次扫描没入库（以「生成并校验配置」那步的 verify 结果为准：defconfig 会重扫一次，很多情况下那时就进去了）"
fi
echo "  第三方包处理完成"
