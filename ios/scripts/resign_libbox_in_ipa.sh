#!/usr/bin/env bash
# Re-sign Libbox.framework inside an exported IPA so codesign Identifier matches
# CFBundleIdentifier after Xcode/Flutter exportArchive.
#
# Keep Mach-O basename "Libbox" (and CFBundleExecutable=Libbox) so
# LC_LOAD_DYLIB=@rpath/Libbox.framework/Libbox stays valid. Do NOT rename the
# binary or run install_name_tool -change on already-signed Runner/PacketTunnel —
# lengthening the load path (Libbox → io.nekohasekai.libbox) without link-time
# header padding corrupts those Mach-Os → ASC 90085 ("No architectures").
#
# Stamp Identifier via codesign --identifier=CFBundleIdentifier (ASC 90334).
# Keep reverse-DNS CFBundleIdentifier (must contain a '.') — a bare "Libbox" id
# lets Xcode append a hash and recreate the mismatch.
#
# Forensic note (TF 1.0.59/37): post-export resign with --timestamp=none and
# soft host verify produced device "Unable to Install" even when ASC accepted
# the upload. Distribution re-sign MUST use secure --timestamp, DER entitlements,
# and hard codesign --verify on Libbox → appex → app.
set -euo pipefail

IPA="${1:?usage: resign_libbox_in_ipa.sh path/to/App.ipa}"
if [[ ! -f "$IPA" ]]; then
  echo "error: IPA not found: $IPA" >&2
  exit 1
fi

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Distribution[^"]*\)".*/\1/p' \
      | head -1
  )"
fi
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(iPhone Distribution[^"]*\)".*/\1/p' \
      | head -1
  )"
fi
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  echo "error: no Apple Distribution identity in keychain" >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
fi

codesign_identifier() {
  local path="$1"
  /usr/bin/codesign -d --verbose=4 "$path" 2>&1 \
    | /usr/bin/sed -n 's/^Identifier=//p' \
    | /usr/bin/head -1
}

# Distribution IPA destined for TestFlight/device must show Apple Distribution
# authority and a secure timestamp. Modern codesign -dvvv prints Timestamp=;
# older tools print Signed Time=. Ad-hoc / timestamp=none signatures upload in
# some cases but installd rejects ("Unable to Install").
assert_distribution_seal() {
  local path="$1"
  local label="${2:-$path}"
  local dump
  dump="$(/usr/bin/codesign -d --verbose=4 "$path" 2>&1 || true)"
  if ! printf '%s\n' "$dump" | /usr/bin/grep -q 'Authority=Apple Distribution'; then
    echo "error: $label missing Authority=Apple Distribution after resign:" >&2
    printf '%s\n' "$dump" >&2
    exit 1
  fi
  # Accept Timestamp= (modern) or Signed Time= (legacy) as secure timestamp proof.
  if ! printf '%s\n' "$dump" | /usr/bin/grep -Eq 'Timestamp=|Signed Time='; then
    echo "error: $label missing Timestamp=/Signed Time= (secure timestamp required; timestamp=none breaks device install):" >&2
    printf '%s\n' "$dump" >&2
    exit 1
  fi
  if printf '%s\n' "$dump" | /usr/bin/grep -qi 'Signature=adhoc'; then
    echo "error: $label looks ad-hoc after resign — refuse upload" >&2
    printf '%s\n' "$dump" >&2
    exit 1
  fi
  echo "Distribution seal OK: $label"
}

# Fail CI before ASC upload if a bundle executable is not a readable arm64 Mach-O.
assert_macho_arm64() {
  local path="$1"
  local label="${2:-$path}"
  if [[ ! -f "$path" ]]; then
    echo "error: missing Mach-O for lipo check: $label ($path)" >&2
    exit 1
  fi
  local size
  size="$(/usr/bin/stat -f%z "$path" 2>/dev/null || /usr/bin/stat -c%s "$path")"
  if [[ "${size:-0}" -lt 1024 ]]; then
    echo "error: $label is too small (${size} bytes) — not a real Mach-O (ASC 90085)" >&2
    exit 1
  fi
  local desc archs
  desc="$(/usr/bin/file -b "$path" 2>/dev/null || true)"
  case "$desc" in
    *Mach-O*) ;;
    *)
      echo "error: $label is not Mach-O ($desc) — ASC 90085" >&2
      exit 1
      ;;
  esac
  archs="$(/usr/bin/lipo -info "$path" 2>&1 || true)"
  if [[ "$archs" != *arm64* ]]; then
    echo "error: $label has no arm64 (lipo: $archs) — ASC 90085" >&2
    /usr/bin/otool -hv "$path" >&2 || true
    exit 1
  fi
  echo "Mach-O arm64 OK: $label ($archs)"
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/resign-libbox.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "Re-signing Libbox in $IPA with identity: $IDENTITY"
ditto -x -k "$IPA" "$TMP"
APP="$(find "$TMP/Payload" -maxdepth 1 -name '*.app' -type d | head -1)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: no Payload/*.app in IPA" >&2
  exit 1
fi

LIBBOX="$APP/Frameworks/Libbox.framework"
BINARY="$LIBBOX/Libbox"
if [[ ! -d "$LIBBOX" || ! -f "$BINARY" ]]; then
  echo "error: missing $LIBBOX/Libbox" >&2
  ls -la "$LIBBOX" >&2 || true
  exit 1
fi

LIBBOX_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIBBOX/Info.plist" 2>/dev/null || true)"
if [[ -z "$LIBBOX_ID" ]]; then
  echo "error: Libbox Info.plist missing CFBundleIdentifier" >&2
  exit 1
fi
EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$LIBBOX/Info.plist" 2>/dev/null || true)"
if [[ "$EXEC" != "Libbox" ]]; then
  echo "error: CFBundleExecutable='$EXEC' must stay Libbox (no post-export rename; ASC 90085)" >&2
  exit 1
fi
RES_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIBBOX/Resources/Info.plist" 2>/dev/null || true)"
if [[ -z "$RES_ID" || "$RES_ID" != "$LIBBOX_ID" ]]; then
  echo "error: Libbox Resources CFBundleIdentifier '$RES_ID' != '$LIBBOX_ID' (ASC 90334)" >&2
  exit 1
fi
# Reject leftover long-name Mach-O from older basename-proof resigns.
if [[ -e "$LIBBOX/$LIBBOX_ID" ]]; then
  echo "error: unexpected $LIBBOX/$LIBBOX_ID — keep short-name Mach-O only" >&2
  exit 1
fi

assert_macho_arm64 "$BINARY" "Libbox.framework/Libbox (pre-sign)"

echo "Stamping Libbox Identifier=$LIBBOX_ID (Mach-O basename stays Libbox)"
# Secure timestamp required for Distribution IPA destined for device install.
/usr/bin/codesign --force --sign "$IDENTITY" --identifier="$LIBBOX_ID" --timestamp "$BINARY"
if ! /usr/bin/codesign --force --sign "$IDENTITY" --identifier="$LIBBOX_ID" --timestamp --generate-entitlement-der "$LIBBOX"; then
  /usr/bin/codesign --force --deep --sign "$IDENTITY" --identifier="$LIBBOX_ID" --timestamp "$LIBBOX"
fi

for path in "$BINARY" "$LIBBOX"; do
  got="$(codesign_identifier "$path")"
  if [[ "$got" != "$LIBBOX_ID" ]]; then
    echo "error: $path Identifier='$got' (want $LIBBOX_ID)" >&2
    exit 1
  fi
  /usr/bin/codesign --verify --verbose=4 "$path"
  assert_distribution_seal "$path" "$(basename "$path")"
done

assert_macho_arm64 "$BINARY" "Libbox.framework/Libbox (post-sign)"

# Re-seal appex then host app so nested Libbox hash changes are valid.
# Do not touch LC_LOAD_DYLIB / install_name_tool on these signed executables.
APPEX="$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' -type d 2>/dev/null | head -1 || true)"
resign_bundle() {
  local bundle="$1"
  local ent="$TMP/$(basename "$bundle").entitlements.plist"
  # Keep embedded.mobileprovision; only refresh code signature + entitlements.
  if [[ ! -f "$bundle/embedded.mobileprovision" ]]; then
    echo "error: missing embedded.mobileprovision in $bundle" >&2
    exit 1
  fi
  /usr/bin/codesign -d --entitlements ":$ent" "$bundle" 2>/dev/null || true
  if [[ ! -f "$ent" || ! -s "$ent" ]]; then
    echo "error: could not extract entitlements from $bundle for re-seal" >&2
    exit 1
  fi
  /usr/bin/codesign --force --sign "$IDENTITY" --entitlements "$ent" \
    --generate-entitlement-der --timestamp "$bundle"
  /usr/bin/codesign --verify --verbose=4 "$bundle"
  assert_distribution_seal "$bundle" "$(basename "$bundle")"
}

if [[ -n "$APPEX" && -d "$APPEX" ]]; then
  echo "Re-signing extension $(basename "$APPEX")"
  resign_bundle "$APPEX"
fi
echo "Re-signing host $(basename "$APP")"
resign_bundle "$APP"

# ASC 90085 targets "bundle executable" — verify host + appex Mach-Os too.
APP_EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null || true)"
if [[ -n "$APP_EXEC" && -f "$APP/$APP_EXEC" ]]; then
  assert_macho_arm64 "$APP/$APP_EXEC" "Runner/$APP_EXEC"
fi
if [[ -n "$APPEX" && -d "$APPEX" ]]; then
  APPEX_EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APPEX/Info.plist" 2>/dev/null || true)"
  if [[ -n "$APPEX_EXEC" && -f "$APPEX/$APPEX_EXEC" ]]; then
    assert_macho_arm64 "$APPEX/$APPEX_EXEC" "PacketTunnel/$APPEX_EXEC"
  fi
fi

OUT="$TMP/repacked.ipa"
(
  cd "$TMP"
  /usr/bin/zip -qry "$OUT" Payload
)
# Replace in place (preserve caller path).
ditto "$OUT" "$IPA"
echo "OK Libbox re-signed in IPA (id $LIBBOX_ID, exec Libbox, no rename)"
