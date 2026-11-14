#!/usr/bin/env bash
# Build Libbox.xcframework from upstream sing-box (macOS / Codemagic).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Must match PacketTunnel Swift (LibboxNewCommandServer(handler, platform, &error),
# StartOrReloadService, WriteMessage(level, message)). v1.12.x uses the old API.
TAG="${LIBBOX_SINGBOX_TAG:-v1.13.21}"
WORK="${TMPDIR:-/tmp}/kpax-libbox-build"
OUT_PLUGIN="$ROOT/third_party/sing_box/ios/Frameworks"
OUT_IOS="$ROOT/ios/Frameworks"
NORM="$SCRIPT_DIR/normalize_libbox_framework.sh"

mkdir -p "$OUT_PLUGIN" "$OUT_IOS" "$WORK"
cd "$WORK"

if [[ ! -d sing-box/.git ]]; then
  rm -rf sing-box
  git clone --depth=1 --single-branch --branch="$TAG" https://github.com/SagerNet/sing-box.git
fi
cd sing-box
# A cached clone must not silently build a previously selected version.
git fetch --depth=1 origin "refs/tags/$TAG:refs/tags/$TAG"
git checkout --detach "$TAG"

export PATH="$PATH:$(go env GOPATH)/bin"
make lib_install

# TestFlight / device IPA: iphoneos arm64 only (default).
# Simulator: LIBBOX_APPLE_PLATFORM=iossimulator LIBBOX_NORMALIZE_SLICES=simulator
# Both:     LIBBOX_APPLE_PLATFORM=ios,iossimulator LIBBOX_NORMALIZE_SLICES=all
APPLE_PLATFORM="${LIBBOX_APPLE_PLATFORM:-ios}"
NORMALIZE_SLICES="${LIBBOX_NORMALIZE_SLICES:-}"
if [[ -z "$NORMALIZE_SLICES" ]]; then
  case "$APPLE_PLATFORM" in
    *simulator*) NORMALIZE_SLICES=all ;;
    *) NORMALIZE_SLICES=device ;;
  esac
fi
export LIBBOX_NORMALIZE_SLICES="$NORMALIZE_SLICES"
echo "Building Libbox.xcframework ($TAG, platform=$APPLE_PLATFORM, normalize=$NORMALIZE_SLICES)"
# Drop previous xcframework so a cached WORK tree cannot leave static simulator
# slices next to a freshly relinked device dylib (CocoaPods mixed linkage).
rm -rf \
  "$WORK/sing-box/Libbox.xcframework" \
  "$WORK/sing-box-for-apple/Libbox.xcframework" \
  "$WORK/Libbox.xcframework"
go run ./cmd/internal/build_libbox -target apple -platform "$APPLE_PLATFORM"

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

# gomobile multi-platform bind emits macOS Versions/A layouts; ASC 90171 rejects
# those binaries unless each iOS slice is a shallow framework with a real dylib.
# Use absolute SCRIPT_DIR — cwd is $WORK/sing-box here, so relative ios/scripts fails.
if [[ ! -f "$NORM" ]]; then
  echo "error: missing $NORM" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$NORM"
export LIBBOX_SINGBOX_TAG="$TAG"
normalize_xcframework "$OUT_PLUGIN/Libbox.xcframework"
normalize_xcframework "$OUT_IOS/Libbox.xcframework"
echo "Libbox.xcframework installed ($TAG) → Frameworks/ (shallow iOS slices)"
