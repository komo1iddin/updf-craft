#!/bin/bash
# depot_tools'ni o'rnatadi (yo'q bo'lsa) va PDFium'ni Engine/PDFIUM_REVISION dagi
# commit'ga sinxronlaydi. Konfiguratsiya: Engine/.gclient ("minimal", rust'siz).
#
#   Engine/scripts/sync_pdfium.sh
set -euo pipefail
ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
REV="$(tr -d '[:space:]' < "$ENGINE/PDFIUM_REVISION")"

if [ ! -x "$ENGINE/depot_tools/gclient" ]; then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git \
    "$ENGINE/depot_tools"
fi
export PATH="$ENGINE/depot_tools:$PATH" DEPOT_TOOLS_UPDATE=0 DEPOT_TOOLS_METRICS=0

cd "$ENGINE"
gclient sync --no-history --shallow -j8 --revision "pdfium@$REV"

# DEPS rust toolchain'ni (GCS dep, ~1.5 GB) shartsiz yuklaydi va gclient custom_deps'ni
# GCS dep'larga qo'llamaydi. enable_rust=false bilan u kerak emas — o'chiramiz.
rm -rf "$ENGINE/pdfium/third_party/rust-toolchain"
"$ENGINE/scripts/link_into_pdfium.sh"
