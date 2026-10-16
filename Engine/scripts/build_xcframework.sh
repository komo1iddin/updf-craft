#!/bin/bash
# CraftCore.xcframework'ni yig'adi: libcraftcore.a (arm64 va bo'lsa x86_64 — lipo bilan
# universal) + craftcore.h + module.modulemap.
#
#   Engine/scripts/build_xcframework.sh
#
# Avval Engine/scripts/build_pdfium.sh arm64 (va ixtiyoriy x64) ishga tushirilgan bo'lishi
# kerak. Natija: Packages/CraftKit/Artifacts/CraftCore.xcframework
set -euo pipefail
ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
PDFIUM="$ENGINE/pdfium"
DEST="$ENGINE/../Packages/CraftKit/Artifacts"

libs=()
for cpu in arm64 x64; do
  lib="$PDFIUM/out/craft-$cpu/obj/craftcore/libcraftcore.a"
  if [ -f "$lib" ]; then libs+=("$lib"); echo "slice: $cpu  ($(du -h "$lib" | cut -f1))"; fi
done
[ ${#libs[@]} -gt 0 ] || { echo "libcraftcore.a topilmadi — avval build_pdfium.sh"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/lib" "$STAGE/include"
if [ ${#libs[@]} -gt 1 ]; then
  lipo -create "${libs[@]}" -output "$STAGE/lib/libcraftcore.a"
else
  cp "${libs[0]}" "$STAGE/lib/libcraftcore.a"
fi
cp "$ENGINE/include/craftcore.h" "$STAGE/include/"
cat > "$STAGE/include/module.modulemap" <<'MAP'
module CraftCore {
    header "craftcore.h"
    export *
}
MAP

mkdir -p "$DEST"
rm -rf "$DEST/CraftCore.xcframework"
xcodebuild -create-xcframework \
  -library "$STAGE/lib/libcraftcore.a" -headers "$STAGE/include" \
  -output "$DEST/CraftCore.xcframework"
lipo -info "$DEST"/CraftCore.xcframework/*/libcraftcore.a
