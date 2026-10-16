#!/bin/bash
# O'z kodimizni PDFium gn daraxtiga symlink qiladi:
#   pdfium/craftcore          -> Engine/craftcore   (//craftcore)
#   pdfium/craftcore_harness  -> Engine/harness     (//craftcore_harness)
#   pdfium/craftcore_include  -> Engine/include     (//craftcore_include)
# PDFium manbasining o'zi o'zgartirilmaydi.
set -euo pipefail
ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
PDFIUM="$ENGINE/pdfium"
[ -d "$PDFIUM/core" ] || { echo "PDFium topilmadi: $PDFIUM (avval gclient sync)"; exit 1; }
for pair in craftcore:craftcore craftcore_harness:harness craftcore_include:include; do
  link="${pair%%:*}"; target="${pair##*:}"
  ln -sfn "../$target" "$PDFIUM/$link"
  echo "$PDFIUM/$link -> ../$target"
done
