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
failed=""

# ---- iStore：按官方 README 的接法 ----
#   ./scripts/feeds update istore
#   ./scripts/feeds install -d y -p istore luci-app-store
# -p istore : 同名包优先用 istore feed（防止被其它 feed 的同名副本顶掉）
# -d y      : 触发 refresh_config('y') → make oldconfig CONFDEFAULT=y；
#             这棵树的 CONFDEFAULT=y 等价于 --allyesconfig，
#             只有在 .config 还不存在时才是无害的 —— 我们正是先装 feeds 再生成 .config。
#             万一以后顺序变了（.config 已存在），这里自动退回不带 -d 的写法。
if [ -f .config ]; then
  echo "  [!] .config 已存在，为免 allyesconfig 全开，本次不带 -d y"
  ISTORE_ARGS="-p istore"
else
  ISTORE_ARGS="-d y -p istore"
fi

# shellcheck disable=SC2086
if ./scripts/feeds install $ISTORE_ARGS luci-app-store; then
  echo "  [ok] luci-app-store（feed: istore）"
else
  echo "  [!]  luci-app-store 安装失败"
  failed="$failed luci-app-store"
fi
echo "  (iStore 19.07+ 需要 luci-compat，已在 config/base.config 里选中)"

# ---- 其余插件：逐个装，某个失败不至于把整步带崩 ----
for pkg in \
    luci-lib-taskd \
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
  echo "::warning::以下包 feeds install 失败：$failed —— 后面会给出具体诊断"
fi

# ----- 补 build 签名 -----
# scan.mk 是这么发现包的：
#   find -L package -name Makefile | xargs grep -E 'call (BuildPackage|KernelPackage|...)'
# 命中的目录才会被 DUMP 成元数据；缺这行签名的包会被静默跳过。
echo "===== 检查 build 签名 ====="
for pkg in luci-app-store luci-lib-taskd luci-lib-xterm taskd ddnsto luci-app-ddnsto \
           luci-app-wechatpush gecoosac luci-app-gecoosac luci-theme-aurora luci-app-aurora-config ; do
  for d in package/feeds/*/"$pkg" package/"$pkg"; do
    [ -f "$d/Makefile" ] || continue
    if ! grep -qE 'call (Build/DefaultTargets|BuildPackage|KernelPackage)' "$d/Makefile"; then
      echo "  [fix] $d/Makefile 缺少 build 签名，补一行注释"
      printf '\n# call BuildPackage - OpenWrt buildroot signature\n' >> "$d/Makefile"
    fi
  done
done
echo "  签名检查完成"

# ----- Aurora 主题 + 设置插件：仓库根目录就是包本体，不能当 feed 用 -----
# 当 feed 用时目录名会变成 feeds/<feed名>，而 luci.mk 的 LUCI_NAME 取的是目录名，
# 包名会算成 "<feed名>" 而不是 luci-theme-aurora，菜单分类也会错。
# 所以按上游 README 的做法：直接 clone 到 package/<包名>。
echo "===== Aurora 主题 + 设置插件 ====="
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

# 主题本体（自带 uci-defaults，装上即设为默认主题）
clone_pkg "https://github.com/ChenLing93/luci-theme-aurora.git" \
          "package/luci-theme-aurora" "Aurora 主题"

# 主题设置界面：5 套预设、配色令牌、导航布局、悬浮工具栏、主题商店
clone_pkg "https://github.com/eamonxg/luci-app-aurora-config.git" \
          "package/luci-app-aurora-config" "Aurora 设置插件"

# ----- 所有包就位后：清扫描缓存 → 全量重扫一次 -----
# 为什么必须清：扫描器把「有哪些包」记在 tmp/info/.files-packageinfo.mk，这个文件
# 是在 make 读取阶段被 -include 的；如果它在本次运行中才被重建，make 不会重新读它，
# 于是「刚装好的包」这一轮里等于不存在 —— 表现为 .config-package.in 没有符号、且毫无报错。
# 我们前面为装 8 个包跑了好几遍 feeds install，正好会踩进这种状态（iStore 就是这么丢的）。
echo "===== 清理扫描缓存，全量重扫 ====="
rm -rf tmp/info \
       tmp/.packageinfo tmp/.targetinfo \
       tmp/.config-package.in tmp/.config-target.in tmp/.config-feeds.in \
       tmp/.packagedeps tmp/.packageauxvars tmp/.packageusergroup tmp/.build 2>/dev/null || true
make -s prepare-tmpinfo >/dev/null 2>&1 || true

for p in luci-app-store luci-theme-aurora luci-app-aurora-config \
         luci-app-wechatpush luci-app-ddnsto gecoosac luci-app-gecoosac ; do
  if grep -qx "config PACKAGE_${p}" tmp/.config-package.in 2>/dev/null; then
    echo "  [ok] $p 已入库"
  else
    echo "  [x] $p 未入库"
  fi
done

# 只在 iStore 真的缺的时候才打印证据，正常情况不刷屏
if { [ -e package/feeds/istore/luci-app-store ] || [ -e package/luci-app-store ]; } \
   && ! grep -qx 'config PACKAGE_luci-app-store' tmp/.config-package.in 2>/dev/null; then
  echo "----- iStore 未入库，逐层取证 -----"

  echo "  1) find 能否发现它的 Makefile"
  { find -L package -maxdepth 5 -name Makefile 2>/dev/null | grep 'luci-app-store' | sed 's/^/       /' ; } || echo "       (find 没找到)"

  echo "  2) Makefile 里的 build 签名命中次数"
  { grep -cE 'call (Build/DefaultTargets|BuildPackage|KernelPackage)' package/feeds/istore/luci-app-store/Makefile 2>/dev/null | sed 's/^/       /' ; } || echo "       (读不到 Makefile)"

  echo "  3) FILELIST 里有没有它"
  { grep -h 'luci-app-store' tmp/info/.files-packageinfo-* 2>/dev/null | sed 's/^/       /' ; } || echo "       (FILELIST 里没有)"

  echo "  4) tmp/info 下的元数据片段（含隐藏文件）"
  { ls -1a tmp/info/ 2>/dev/null | grep -i 'istore' | sed 's/^/       /' ; } || echo "       (没有 istore 片段)"

  echo "  5) DUMP 失败日志"
  dlog="$(find logs -path '*luci-app-store/dump.txt' 2>/dev/null | head -1 || true)"
  if [ -n "$dlog" ]; then
    tail -40 "$dlog" | sed 's/^/       /' || true
  else
    echo "       (没有 logs/.../luci-app-store/dump.txt → 没走到 DUMP)"
  fi

  echo "  6) 手动重跑 DUMP（带 TOPDIR，否则 \$(TOPDIR) 为空会报 /feeds/...）"
  if [ -d package/feeds/istore/luci-app-store ]; then
    { make -r DUMP=1 FEED=istore TOPDIR="$PWD" -C package/feeds/istore/luci-app-store 2>&1 | tail -30 | sed 's/^/       /' ; } || true
  fi

  echo "::warning::iStore 未入库，固件会照常编译但不含 iStore（上面是原因）"
fi

echo "  第三方包处理完成"
