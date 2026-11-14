#!/usr/bin/env bash
# Turn gomobile Versions/A Libbox.framework slices into shallow iOS frameworks
# App Store accepts (ASC 90171 if binary is not a valid CFBundleExecutable).
set -euo pipefail

patch_plist() {
  local plist="$1"
  local platform="$2" # iPhoneOS | iPhoneSimulator
  local pb=/usr/libexec/PlistBuddy
  if [[ ! -f "$plist" ]]; then
    /usr/bin/plutil -create xml1 "$plist"
  fi
  set_or_add() {
    local key="$1" type="$2" val="$3"
    if $pb -c "Print :$key" "$plist" >/dev/null 2>&1; then
      $pb -c "Set :$key $val" "$plist"
    else
      $pb -c "Add :$key $type $val" "$plist"
    fi
  }
  set_or_add CFBundleInfoDictionaryVersion string 6.0
  set_or_add CFBundlePackageType string FMWK
  set_or_add CFBundleExecutable string Libbox
  set_or_add CFBundleIdentifier string io.nekohasekai.libbox
  set_or_add CFBundleName string Libbox
  set_or_add CFBundleVersion string 1
  set_or_add CFBundleShortVersionString string "${LIBBOX_SINGBOX_TAG:-1.13.21}"
  set_or_add MinimumOSVersion string 15.0
  $pb -c "Delete :CFBundleSupportedPlatforms" "$plist" >/dev/null 2>&1 || true
  $pb -c "Add :CFBundleSupportedPlatforms array" "$plist"
  $pb -c "Add :CFBundleSupportedPlatforms:0 string $platform" "$plist"
}

normalize_one() {
  local framework="$1"
  local platform="$2"
  [[ -d "$framework" ]] || return 0

  if [[ -d "$framework/Versions/A" ]]; then
    echo "Shallow-copy $framework from Versions/A"
    local shallow="${framework}.shallow"
    rm -rf "$shallow"
    /usr/bin/ditto "$framework/Versions/A" "$shallow"
    rm -rf "$framework"
    mv "$shallow" "$framework"
  fi

  if [[ -f "$framework/Resources/Info.plist" && ! -f "$framework/Info.plist" ]]; then
    cp "$framework/Resources/Info.plist" "$framework/Info.plist"
  fi

  patch_plist "$framework/Info.plist" "$platform"
  mkdir -p "$framework/Resources"
  cp "$framework/Info.plist" "$framework/Resources/Info.plist"

  local binary="$framework/Libbox"
  if [[ ! -f "$binary" ]]; then
    echo "error: missing $binary after normalize" >&2
    ls -laR "$framework" >&2 || true
    exit 1
  fi
  local size
  size=$(/usr/bin/stat -f%z "$binary" 2>/dev/null || /usr/bin/stat -c%s "$binary")
  if [[ "${size:-0}" -lt 1000000 ]]; then
    echo "error: Libbox too small ($size) at $binary" >&2
    exit 1
  fi

  local desc
  desc=$(/usr/bin/file -b "$binary" || true)
  case "$desc" in
    *dynamically\ linked*|*shared\ library*|*Mach-O*dylib*)
      ;;
    *)
      echo "error: Libbox is not a dylib ($desc) — would trigger ASC 90171" >&2
      exit 1
      ;;
  esac

  /usr/bin/install_name_tool -id "@rpath/Libbox.framework/Libbox" "$binary" 2>/dev/null || true
  echo "OK normalized $framework ($size bytes, $platform)"
}

normalize_xcframework() {
  local xc="$1"
  [[ -d "$xc" ]] || { echo "error: missing $xc" >&2; exit 1; }
  local fw platform
  for fw in "$xc"/ios-*/Libbox.framework; do
    [[ -d "$fw" ]] || continue
    platform=iPhoneOS
    case "$fw" in
      *simulator*) platform=iPhoneSimulator ;;
    esac
    normalize_one "$fw" "$platform"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "usage: $0 path/to/Libbox.xcframework ..." >&2
    exit 2
  fi
  for arg in "$@"; do
    normalize_xcframework "$arg"
  done
fi
