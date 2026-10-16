#!/bin/bash
# harness smoke test: Tests/corpus ustida open / render / text (CI uchun ham).
#
#   Engine/scripts/smoke_test.sh [arm64|x64]
set -euo pipefail
CPU="${1:-arm64}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
H="$ROOT/Engine/pdfium/out/craft-$CPU/craft-harness"
C="$ROOT/Tests/corpus"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

"$H" open "$C/hello.pdf" | grep -q "sahifalar: 2" || fail "open: sahifalar soni"
"$H" open "$C/rotated.pdf" | grep -q "600.00 x 400.00" || fail "open: /Rotate 90 o'lchami"

"$H" render "$C/hello.pdf" --page 1 --scale 2 "$TMP/p1.png" >/dev/null
[ "$(sips -g pixelWidth -g pixelHeight "$TMP/p1.png" | awk '/pixel/{printf "%s ", $2}')" = "1191 1684 " ] \
  || fail "render: PNG o'lchami"
"$H" render "$C/hello.pdf" --page 2 --scale 0.5 --tile 10,10,100,50 "$TMP/t.png" >/dev/null
[ "$(sips -g pixelWidth "$TMP/t.png" | awk '/pixel/{print $2}')" = "100" ] || fail "render: tile"

"$H" text "$C/hello.pdf" --page 1 | grep -q "Hello, UPDF Craft" || fail "text"
if "$H" render "$C/hello.pdf" --page 9 --scale 1 "$TMP/x.png" 2>/dev/null; then
  fail "mavjud bo'lmagan sahifa xato bermadi"
fi
echo "smoke test ($CPU): OK"
