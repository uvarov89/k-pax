#!/usr/bin/env bash
# Turn gomobile Versions/A Libbox.framework slices into shallow iOS frameworks
# App Store accepts (ASC 90171 if binary is not a valid CFBundleExecutable).
#
# sagernet/gomobile bind uses -buildmode=c-archive and places the .a (via lipo)
# as Versions/A/Libbox. Embedding into Runner.app/Frameworks requires a dylib,
# so archives are relinked with clang -dynamiclib here.
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

# clang flags shared when turning a Go c-archive into a loadable framework dylib.
_libbox_link_libs() {
  echo \
    -framework Foundation \
    -framework CoreFoundation \
    -framework Security \
    -framework Network \
    -framework SystemConfiguration \
    -framework CFNetwork \
    -lresolv \
    -lobjc \
    -lc++
}

relink_archive_to_dylib() {
  local binary="$1"
  local platform="$2" # iPhoneOS | iPhoneSimulator
  local sdk=iphoneos
  local min_flag="-miphoneos-version-min=15.0"
  if [[ "$platform" == "iPhoneSimulator" ]]; then
    sdk=iphonesimulator
    min_flag="-mios-simulator-version-min=15.0"
  fi
  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/libbox-relink.XXXXXX")"

  local archs
  archs="$(lipo -archs "$binary")"
  echo "Relink archive → dylib ($platform, sdk=$sdk, archs=$archs)"

  local outs=()
  local arch thin out target
  for arch in $archs; do
    thin="$tmp/Libbox-$arch.a"
    out="$tmp/Libbox-$arch.dylib"
    lipo "$binary" -thin "$arch" -output "$thin"
    if [[ "$sdk" == "iphonesimulator" ]]; then
      target="${arch}-apple-ios15.0-simulator"
    else
      target="${arch}-apple-ios15.0"
    fi
    # force_load pulls all Go/cgo objects out of the archive into the dylib.
    # shellcheck disable=SC2046
    xcrun clang -dynamiclib \
      -target "$target" \
      -isysroot "$sysroot" \
      $min_flag \
      -install_name "@rpath/Libbox.framework/Libbox" \
      -Wl,-force_load,"$thin" \
      $(_libbox_link_libs) \
      -o "$out"
    outs+=("$out")
  done

  if [[ ${#outs[@]} -eq 1 ]]; then
    cp "${outs[0]}" "$binary"
  else
    lipo -create "${outs[@]}" -output "$binary"
  fi
  chmod +x "$binary" || true
  rm -rf "$tmp"
}

is_dylib() {
  local desc="$1"
  case "$desc" in
    *dynamically\ linked*|*shared\ library*|*Mach-O*dylib*) return 0 ;;
    *) return 1 ;;
  esac
}

is_archive() {
  local desc="$1"
  case "$desc" in
    *ar\ archive*|*current\ ar\ archive*|*ar\ archive\ random\ library*) return 0 ;;
    *) return 1 ;;
  esac
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
  if is_archive "$desc"; then
    relink_archive_to_dylib "$binary" "$platform"
    size=$(/usr/bin/stat -f%z "$binary" 2>/dev/null || /usr/bin/stat -c%s "$binary")
    desc=$(/usr/bin/file -b "$binary" || true)
  fi

  if ! is_dylib "$desc"; then
    echo "error: Libbox is not a dylib ($desc) — would trigger ASC 90171" >&2
    exit 1
  fi

  /usr/bin/install_name_tool -id "@rpath/Libbox.framework/Libbox" "$binary" 2>/dev/null || true
  echo "OK normalized $framework ($size bytes, $platform)"
}

normalize_xcframework() {
  local xc="$1"
  [[ -d "$xc" ]] || { echo "error: missing $xc" >&2; exit 1; }
  echo "Normalize iOS slices in $xc"
  local fw platform
  local found=0
  for fw in "$xc"/ios-*/Libbox.framework; do
    [[ -d "$fw" ]] || continue
    found=1
    platform=iPhoneOS
    case "$fw" in
      *simulator*) platform=iPhoneSimulator ;;
    esac
    normalize_one "$fw" "$platform"
  done
  if [[ "$found" -eq 0 ]]; then
    echo "error: no ios-*/Libbox.framework under $xc" >&2
    ls -la "$xc" >&2 || true
    exit 1
  fi
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
