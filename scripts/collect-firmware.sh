#!/usr/bin/env bash
# @id: collect-firmware.sh
# 把 bin/targets/qualcommax/ipq60xx 下各机型的镜像分别打包，便于下载/刷机。
# 用法: collect-firmware.sh <固件目录> <输出目录> <机型列表>
#   例: collect-firmware.sh openwrt/bin/targets/qualcommax/ipq60xx dist "redmi_ax5 zn_m2 link_nn6000-v2"
set -euo pipefail

BIN_DIR="${1:?用法: collect-firmware.sh <固件目录> <输出目录> <机型列表>}"
OUT_DIR="${2:?缺少输出目录}"
DEVICES="${3:?缺少机型列表}"

if [ ! -d "$BIN_DIR" ]; then
  echo "::error::固件目录不存在：$BIN_DIR"
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

stamp="$(date -u +%Y%m%d)"

for dev in $DEVICES; do
  files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$BIN_DIR" -maxdepth 1 -type f \
    \( -name "*-${dev}.bin"   -o -name "*-${dev}.itb" -o -name "*-${dev}.img" \
    -o -name "*-${dev}.tar"   -o -name "*-${dev}.ubi" -o -name "*-${dev}.trx" \
    -o -name "*-${dev}-*.bin" -o -name "*-${dev}-*.itb" -o -name "*-${dev}-*.img" \
    -o -name "*-${dev}-*.tar" -o -name "*-${dev}-*.ubi" \) | sort)

  if [ "${#files[@]}" -eq 0 ]; then
    echo "::error::没有找到机型 ${dev} 的固件文件，编译可能没选上该机型"
    ls -lh "$BIN_DIR" || true
    exit 1
  fi

  names=()
  for f in "${files[@]}"; do
    names+=("$(basename "$f")")
  done

  tar -czf "$OUT_DIR/${dev}-${stamp}.tar.gz" -C "$BIN_DIR" "${names[@]}"
  printf '%s\n' "${names[@]}" > "$OUT_DIR/${dev}-files.txt"
  echo "已打包 ${dev}: ${#names[@]} 个文件 -> ${dev}-${stamp}.tar.gz"
done

# manifest / profiles 等元数据直接带上，方便核对内核与 NSS 包
for f in "$BIN_DIR"/*.manifest "$BIN_DIR"/profiles.json "$BIN_DIR"/sha256sums; do
  if [ -f "$f" ]; then
    cp "$f" "$OUT_DIR/"
  fi
done

echo "产物目录：$OUT_DIR"
ls -lh "$OUT_DIR"
