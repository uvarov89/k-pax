#!/usr/bin/env bash
# Build Libbox.xcframework from upstream sing-box (macOS / Codemagic).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${LIBBOX_SINGBOX_TAG:-v1.12.12}"
WORK="${TMPDIR:-/tmp}/kpax-libbox-build"
OUT_PLUGIN="$ROOT/third_party/sing_box/ios/Frameworks"
OUT_IOS="$ROOT/ios/Frameworks"

mkdir -p "$OUT_PLUGIN" "$OUT_IOS" "$WORK"
cd "$WORK"

if [[ ! -d sing-box/.git ]]; then
  rm -rf sing-box
  git clone --depth=1 --single-branch --branch="$TAG" https://github.com/SagerNet/sing-box.git
fi
cd sing-box

export PATH="$PATH:$(go env GOPATH)/bin"
make lib_install

# Prefer Makefile target when present; fall back to gomobile bind helper.
if make -n lib_apple >/dev/null 2>&1; then
  make lib_apple
elif make -n ios >/dev/null 2>&1; then
  make ios
else
  go run ./cmd/internal/build_libbox -target apple -platform ios
fi

FRAMEWORK=""
for cand in \
  "$WORK/sing-box/Libbox.xcframework" \
  "$WORK/sing-box-for-apple/Libbox.xcframework" \
  "$WORK/Libbox.xcframework"
do
  if [[ -d "$cand" ]]; then
    FRAMEWORK="$cand"
    break
  fi
done

if [[ -z "$FRAMEWORK" ]]; then
  echo "Libbox.xcframework not found after build" >&2
  find "$WORK" -name 'Libbox.xcframework' -type d 2>/dev/null | head
  exit 1
fi

rm -rf "$OUT_PLUGIN/Libbox.xcframework" "$OUT_IOS/Libbox.xcframework"
cp -R "$FRAMEWORK" "$OUT_PLUGIN/Libbox.xcframework"
cp -R "$FRAMEWORK" "$OUT_IOS/Libbox.xcframework"
echo "Libbox.xcframework installed ($TAG) → Frameworks/"
