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

# 机型名之间有前缀关系：redmi_ax5 ⊂ redmi_ax5-jdcloud。
# 如果按 "*-redmi_ax5-*" 匹配，jdcloud 的镜像也会被算进 redmi_ax5 的包里。
# 所以先收集全部镜像，再按「机型名长度从长到短」认领，长名先拿走自己的文件。
all_files="$(find "$BIN_DIR" -maxdepth 1 -type f \
  \( -name '*.bin' -o -name '*.itb' -o -name '*.img' \
  -o -name '*.tar' -o -name '*.ubi' -o -name '*.trx' \) | sort)"
devices_sorted="$(for d in $DEVICES; do printf '%s %s\n' "$(printf '%s' "$d" | wc -c)" "$d"; done \
                  | sort -rn | awk '{print $2}')"
echo "打包顺序（按名字长度，长的先认领）: $(echo $devices_sorted)"

claimed=" "
for dev in $devices_sorted; do
  files=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$claimed" in
      *" $f "*) continue ;;
    esac
    files+=("$f")
    claimed="$claimed$f "
  done < <(printf '%s\n' "$all_files" | grep -E -- "-${dev}[.-]" || true)

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

# ---- 尺寸提醒 ----
# 这几个机型的设备定义里没有 IMAGE_SIZE，镜像超了 buildroot 不会报错，
# 是刷机的时候才写不进去（甚至刷一半失败）。
# 128MB flash 的 nand 机型（AX5 / ZN-M2）用 60MB 当警戒线：超了不一定刷不进，
# 但 overlay 会很小；实测镜像一般 30~50MB，离上限还远。
LIMIT_MB="${IMAGE_WARN_MB:-60}"
big=""
echo "镜像尺寸："
while IFS= read -r f; do
  [ -f "$f" ] || continue
  mb=$(( $(stat -c%s "$f") / 1048576 ))
  echo "  $(basename "$f") = ${mb}MB"
  if [ "$mb" -ge "$LIMIT_MB" ]; then
    big="$big $(basename "$f")=${mb}MB"
  fi
done < <(find "$BIN_DIR" -maxdepth 1 -type f \
         \( -name '*sysupgrade.bin' -o -name '*factory.bin' -o -name '*.itb' -o -name '*.ubi' \) | sort)

if [ -n "$big" ]; then
  echo "::warning::以下镜像超过 ${LIMIT_MB}MB，128MB flash 的机型（AX5 / ZN-M2）overlay 会很小：$big"
else
  echo "镜像尺寸均在 ${LIMIT_MB}MB 以内（sysupgrade / factory / itb / ubi）"
fi

# manifest / profiles 等元数据直接带上，方便核对内核与 NSS 包
for f in "$BIN_DIR"/*.manifest "$BIN_DIR"/profiles.json "$BIN_DIR"/sha256sums; do
  if [ -f "$f" ]; then
    cp "$f" "$OUT_DIR/"
  fi
done

echo "产物目录：$OUT_DIR"
ls -lh "$OUT_DIR"
