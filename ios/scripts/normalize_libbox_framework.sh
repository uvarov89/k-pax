#!/usr/bin/env bash
# Turn gomobile Versions/A Libbox.framework slices into shallow iOS frameworks
# App Store accepts (ASC 90171 if binary is not a valid CFBundleExecutable).
#
# sagernet/gomobile bind uses -buildmode=c-archive and places the .a (via lipo)
# as Versions/A/Libbox. Embedding into Runner.app/Frameworks requires a dylib,
# so archives are relinked with clang -dynamiclib here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KQUEUE_STUB="${SCRIPT_DIR}/libbox_message_pump_kqueue_stub.cpp"

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

# Cronet (naive) pulls UIKit / telephony / UTType / LocalAuthentication / …
_libbox_link_libs() {
  echo \
    -framework Foundation \
    -framework CoreFoundation \
    -framework Security \
    -framework Network \
    -framework SystemConfiguration \
    -framework CFNetwork \
    -framework UIKit \
    -framework CoreTelephony \
    -framework UniformTypeIdentifiers \
    -framework LocalAuthentication \
    -framework CryptoTokenKit \
    -framework CoreGraphics \
    -framework CoreText \
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

  if [[ ! -f "$KQUEUE_STUB" ]]; then
    echo "error: missing Cronet stub $KQUEUE_STUB" >&2
    exit 1
  fi

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/libbox-relink.XXXXXX")"

  local archs
  archs="$(lipo -archs "$binary")"
  echo "Relink archive → dylib ($platform, sdk=$sdk, archs=$archs)"

  local outs=()
  local arch thin out target stub_o
  for arch in $archs; do
    thin="$tmp/Libbox-$arch.a"
    out="$tmp/Libbox-$arch.dylib"
    stub_o="$tmp/kqueue-stub-$arch.o"
    lipo "$binary" -thin "$arch" -output "$thin"
    if [[ "$sdk" == "iphonesimulator" ]]; then
      target="${arch}-apple-ios15.0-simulator"
    else
      target="${arch}-apple-ios15.0"
    fi
    xcrun clang++ -c -std=c++17 \
      -target "$target" \
      -isysroot "$sysroot" \
      $min_flag \
      -o "$stub_o" \
      "$KQUEUE_STUB"
    # force_load pulls all Go/cgo/Cronet objects out of the archive into the dylib.
    # shellcheck disable=SC2046
    xcrun clang++ -dynamiclib \
      -target "$target" \
      -isysroot "$sysroot" \
      $min_flag \
      -install_name "@rpath/Libbox.framework/Libbox" \
      -Wl,-force_load,"$thin" \
      "$stub_o" \
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

# Drop slices that do not match mode and rewrite root Info.plist so CocoaPods
# never sees mixed static (leftover archive) + dynamic (relinked) libraries.
prune_xcframework_slices() {
  local xc="$1"
  local mode="$2"
  local id keep plist pb=/usr/libexec/PlistBuddy
  local -a remove_ids=()

  plist="$xc/Info.plist"
  [[ -f "$plist" ]] || return 0

  # Walk AvailableLibraries by index until miss.
  local i=0
  while $pb -c "Print :AvailableLibraries:$i:LibraryIdentifier" "$plist" >/dev/null 2>&1; do
    id="$($pb -c "Print :AvailableLibraries:$i:LibraryIdentifier" "$plist")"
    keep=0
    case "$mode" in
      device)
        # Pure device arm64 only — not ios-arm64_x86_64 or *-simulator.
        [[ "$id" == "ios-arm64" ]] && keep=1
        ;;
      simulator)
        case "$id" in *simulator*) keep=1 ;; esac
        ;;
      all)
        case "$id" in
          *macos*|*tvos*) keep=0 ;;
          ios-arm64|*simulator*) keep=1 ;;
        esac
        ;;
    esac
    if [[ "$keep" -eq 0 ]]; then
      remove_ids+=("$id")
    fi
    i=$((i + 1))
  done

  for id in "${remove_ids[@]+"${remove_ids[@]}"}"; do
    echo "Prune xcframework slice $id (mode=$mode)"
    rm -rf "$xc/$id"
    # Remove matching AvailableLibraries entry (scan each time — indices shift).
    i=0
    while $pb -c "Print :AvailableLibraries:$i:LibraryIdentifier" "$plist" >/dev/null 2>&1; do
      local cur
      cur="$($pb -c "Print :AvailableLibraries:$i:LibraryIdentifier" "$plist")"
      if [[ "$cur" == "$id" ]]; then
        $pb -c "Delete :AvailableLibraries:$i" "$plist"
        break
      fi
      i=$((i + 1))
    done
  done

  # Also remove any leftover dirs not listed (cache residue).
  local dir base
  for dir in "$xc"/*; do
    [[ -d "$dir" ]] || continue
    base="$(basename "$dir")"
    case "$base" in
      _CodeSignature) continue ;;
    esac
    keep=0
    case "$mode" in
      device)
        [[ "$base" == "ios-arm64" ]] && keep=1
        ;;
      simulator)
        case "$base" in *simulator*) keep=1 ;; esac
        ;;
      all)
        case "$base" in
          ios-arm64|ios-*-simulator|ios-arm64_*-simulator) keep=1 ;;
        esac
        ;;
    esac
    if [[ "$keep" -eq 0 ]]; then
      echo "Prune leftover dir $base (mode=$mode)"
      rm -rf "$dir"
    fi
  done
}

assert_xcframework_all_dylibs() {
  local xc="$1"
  local fw binary desc
  for fw in "$xc"/*/Libbox.framework; do
    [[ -d "$fw" ]] || continue
    binary="$fw/Libbox"
    [[ -f "$binary" ]] || { echo "error: missing $binary" >&2; exit 1; }
    desc=$(/usr/bin/file -b "$binary" || true)
    if ! is_dylib "$desc"; then
      echo "error: mixed/static Libbox in $fw ($desc) — CocoaPods rejects static+dynamic xcframeworks" >&2
      exit 1
    fi
  done
}

# LIBBOX_NORMALIZE_SLICES=device|simulator|all (default: device for TestFlight)
normalize_xcframework() {
  local xc="$1"
  [[ -d "$xc" ]] || { echo "error: missing $xc" >&2; exit 1; }
  local mode="${LIBBOX_NORMALIZE_SLICES:-device}"
  echo "Normalize iOS slices in $xc (mode=$mode)"
  local fw platform
  local found=0
  local slices=()

  # Drop simulator (or device) residue before relink so CocoaPods never sees
  # archive + dylib in one xcframework (gomobile -target ios may emit both).
  prune_xcframework_slices "$xc" "$mode"

  # Device first, then simulator — deterministic order independent of glob locale.
  case "$mode" in
    device)
      for fw in "$xc"/ios-arm64/Libbox.framework "$xc"/ios-arm64_*/Libbox.framework; do
        [[ -d "$fw" ]] || continue
        case "$fw" in *simulator*) continue ;; esac
        slices+=("$fw")
      done
      ;;
    simulator)
      for fw in "$xc"/ios-*-simulator/Libbox.framework; do
        [[ -d "$fw" ]] || continue
        slices+=("$fw")
      done
      ;;
    all)
      for fw in "$xc"/ios-arm64/Libbox.framework "$xc"/ios-arm64_*/Libbox.framework; do
        [[ -d "$fw" ]] || continue
        case "$fw" in *simulator*) continue ;; esac
        slices+=("$fw")
      done
      for fw in "$xc"/ios-*-simulator/Libbox.framework; do
        [[ -d "$fw" ]] || continue
        slices+=("$fw")
      done
      ;;
    *)
      echo "error: LIBBOX_NORMALIZE_SLICES must be device|simulator|all (got $mode)" >&2
      exit 1
      ;;
  esac

  for fw in "${slices[@]+"${slices[@]}"}"; do
    [[ -d "$fw" ]] || continue
    found=1
    platform=iPhoneOS
    case "$fw" in
      *simulator*) platform=iPhoneSimulator ;;
    esac
    normalize_one "$fw" "$platform"
  done
  if [[ "$found" -eq 0 ]]; then
    echo "error: no matching ios Libbox.framework under $xc (mode=$mode)" >&2
    ls -la "$xc" >&2 || true
    exit 1
  fi
  assert_xcframework_all_dylibs "$xc"
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
