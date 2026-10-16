#!/bin/bash
# PDFium + craftcore + harness'ni bitta arxitektura uchun yig'adi.
#
#   Engine/scripts/build_pdfium.sh [arm64|x64] [debug]
#
# Natija: Engine/pdfium/out/craft-<cpu>/obj/craftcore/libcraftcore.a
#         Engine/pdfium/out/craft-<cpu>/craft-harness
set -euo pipefail
CPU="${1:-arm64}"
MODE="${2:-release}"
ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
PDFIUM="$ENGINE/pdfium"

case "$CPU" in arm64|x64) ;; *) echo "noma'lum cpu: $CPU (arm64 yoki x64)"; exit 2;; esac
IS_DEBUG=false; [ "$MODE" = debug ] && IS_DEBUG=true
OUT="out/craft-$CPU"; [ "$MODE" = debug ] && OUT="out/craft-$CPU-debug"

"$ENGINE/scripts/link_into_pdfium.sh" >/dev/null

ARGS="
target_os=\"mac\"
target_cpu=\"$CPU\"
is_debug=$IS_DEBUG
pdf_is_standalone=true
is_component_build=false
pdf_enable_v8=false
pdf_enable_xfa=false
use_custom_libcxx=false
pdf_use_partition_alloc=false
pdf_use_skia=false
enable_rust=false
use_remoteexec=false
use_siso=false
symbol_level=0
mac_deployment_target=\"14.0\"
# Upstream unsafe-buffers tekshiruvi Chromium libc++ (bounded iterator) bilan ishlashga
# mo'ljallangan; Apple libc++ bilan (use_custom_libcxx=false) std::array iteratorlari
# xom pointer bo'lib, -Werror bilan yiqiladi. Shuning uchun o'chiriladi.
clang_unsafe_buffers_paths=\"\"
"

cd "$PDFIUM"
mkdir -p "$OUT"
printf '%s\n' "$ARGS" > "$OUT/args.gn"
# depot_tools wrapper'lari o'rniga checkout ichidagi binarlar (python bootstrap shart emas).
buildtools/mac/gn gen "$OUT" --root-target=//craftcore
third_party/ninja/ninja -C "$OUT" craftcore harness
echo
ls -lh "$OUT/obj/craftcore/libcraftcore.a" "$OUT/craft-harness"
