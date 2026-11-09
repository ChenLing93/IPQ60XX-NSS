#!/usr/bin/env bash
# 给 IPQ6000/IPQ6010 板子的设备树补上 1320 / 1440 / 1512 MHz 三档 OPP。
#
# 背景（2026-11 实测）：
#   上游内核的 ipq6018.dtsi 里 cpu_opp_table 只有 864 / 1056 / 1200 三档；
#   LibWrt 的 ipq6018-common.dtsi 只给 1320/1440/1512 写了 opp-supported-hw，
#   没写 opp-hz —— 节点是空的，cpufreq-dt 直接跳过，于是只能看到三档。
#   而板级 dts（ipq6000-*.dts）里补一个 opp-hz 就够了，电压由 CPR/board 决定。
#
# 用法: patch-cpu-opp.sh <dts目录>
#   例: patch-cpu-opp.sh openwrt/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom
#
# 幂等：文件里已经有 opp-1512000000 就跳过。
set -euo pipefail

DTS_DIR="${1:?用法: patch-cpu-opp.sh <dts目录>}"
if [ ! -d "$DTS_DIR" ]; then
  echo "::error::找不到 dts 目录：$DTS_DIR"
  exit 1
fi

patched=0
skipped=0
for f in "$DTS_DIR"/ipq6000-*.dts "$DTS_DIR"/ipq6010-*.dts; do
  [ -f "$f" ] || continue
  if grep -q 'opp-1512000000' "$f"; then
    skipped=$((skipped + 1))
    continue
  fi

  cat >> "$f" <<'EOF'

/* ==== 补高档 OPP（上游 ipq6018.dtsi 默认只到 1200MHz）====
 * 1320 / 1440 / 1512 三档；不加电压属性，由 CPR/board 决定。
 */
&cpu_opp_table {
	opp-1320000000 {
		opp-hz = /bits/ 64 <1320000000>;
	};
	opp-1440000000 {
		opp-hz = /bits/ 64 <1440000000>;
	};
	opp-1512000000 {
		opp-hz = /bits/ 64 <1512000000>;
	};
};
EOF
  echo "  [补] $(basename "$f")"
  patched=$((patched + 1))
done

echo "已补 OPP 的 dts：$patched 个（跳过 $skipped 个已含 1512 的）"
if [ "$patched" -eq 0 ] && [ "$skipped" -eq 0 ]; then
  echo "::warning::一个 ipq6000/ipq6010 dts 都没找到，路径对不对？$DTS_DIR"
fi
