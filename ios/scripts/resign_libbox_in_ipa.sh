#!/usr/bin/env bash
# Post-export IPA fix for Libbox.framework so installd accepts the build.
#
# History (TF 1.0.59):
# - Identifier-only resign with Mach-O basename still "Libbox" uploads OK but
#   device shows "Unable to Install" — installd wants basename == Identifier.
# - Renaming + install_name_tool -change on *already-signed* Runner/PacketTunnel
#   corrupted Mach-Os → ASC 90085 ("No architectures").
#
# Durable approach (this script, post-export only):
# 1) codesign --remove-signature nested-first (binary → framework → appex → app)
# 2) Rename Mach-O Libbox → CFBundleIdentifier; CFBundleExecutable = that name
# 3) Symlink Libbox → long name so LC_LOAD_DYLIB=@rpath/Libbox.framework/Libbox
#    still resolves WITHOUT lengthening host load commands (safer than -change)
# 4) install_name_tool -id to the long path on the *unsigned* Libbox binary
#    (best-effort; symlink covers loads if header has no room to grow)
# 5) Best-effort -change on unsigned host Mach-Os; symlink is the fallback
# 6) Re-sign Libbox → framework → appex → app with Apple Distribution,
#    --identifier matching each bundle id, secure --timestamp (not none)
#
# Normalize/build keep basename Libbox for Xcode -framework Libbox linking.
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

SHORT_EXEC="Libbox"
OLD_LOAD="@rpath/Libbox.framework/${SHORT_EXEC}"

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

# Resolve symlinks to an absolute path. macOS readlink has no portable -f;
# stating a Versions/... symlink itself reports ~11B (link text), not the Mach-O
# — that false "ASC 90085 too small" aborted Codemagic resign on M2.
resolve_real_file() {
  local path="$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    echo ""
    return 0
  fi
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path"
}

# Fail CI before ASC upload if a bundle executable is not a readable arm64 Mach-O.
assert_macho_arm64() {
  local path="$1"
  local label="${2:-$path}"
  path="$(resolve_real_file "$path")"
  if [[ -z "$path" || ! -f "$path" ]]; then
    echo "error: missing Mach-O for lipo check: $label ($path)" >&2
    exit 1
  fi
  local size
  size="$(/usr/bin/stat -f%z "$path" 2>/dev/null || /usr/bin/stat -c%s "$path")"
  if [[ "${size:-0}" -lt 1024 ]]; then
    echo "error: $label is too small (${size} bytes) — not a real Mach-O (ASC 90085)" >&2
    ls -la "$(dirname "$path")" >&2 || true
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

remove_signature() {
  local path="$1"
  local label="${2:-$path}"
  if [[ ! -e "$path" ]]; then
    return 0
  fi
  echo "Removing signature: $label"
  /usr/bin/codesign --remove-signature "$path" 2>/dev/null || true
}

# Rewrite LC_LOAD_DYLIB only on unsigned Mach-Os. Prefer success; on failure
# (no headerpad for a longer path) the Libbox → long-name symlink covers loads.
try_change_load() {
  local macho="$1"
  local label="${2:-$macho}"
  local new_load="$3"
  if [[ ! -f "$macho" || -L "$macho" ]]; then
    return 0
  fi
  local loads
  loads="$(/usr/bin/otool -L "$macho" 2>/dev/null || true)"
  if ! printf '%s\n' "$loads" | /usr/bin/grep -Fq "$OLD_LOAD"; then
    return 0
  fi
  if /usr/bin/install_name_tool -change "$OLD_LOAD" "$new_load" "$macho" 2>/dev/null; then
    echo "OK install_name_tool -change on $label"
  else
    echo "warn: install_name_tool -change failed on $label (no headerpad?) — Libbox symlink covers $OLD_LOAD"
  fi
}

macho_loads_libbox() {
  local macho="$1"
  [[ -f "$macho" && ! -L "$macho" ]] || return 1
  /usr/bin/otool -L "$macho" 2>/dev/null | /usr/bin/grep -Fq "$OLD_LOAD"
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
SHORT_BINARY="$LIBBOX/$SHORT_EXEC"
if [[ ! -d "$LIBBOX" ]]; then
  echo "error: missing $LIBBOX" >&2
  exit 1
fi
if [[ ! -f "$SHORT_BINARY" && ! -L "$SHORT_BINARY" ]]; then
  # Already renamed in a prior partial run? Accept long name if present.
  LIBBOX_ID_PREVIEW="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIBBOX/Info.plist" 2>/dev/null || true)"
  if [[ -n "$LIBBOX_ID_PREVIEW" && -f "$LIBBOX/$LIBBOX_ID_PREVIEW" ]]; then
    SHORT_BINARY="$LIBBOX/$LIBBOX_ID_PREVIEW"
  else
    echo "error: missing $LIBBOX/$SHORT_EXEC" >&2
    ls -la "$LIBBOX" >&2 || true
    exit 1
  fi
fi

LIBBOX_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIBBOX/Info.plist" 2>/dev/null || true)"
if [[ -z "$LIBBOX_ID" ]]; then
  echo "error: Libbox Info.plist missing CFBundleIdentifier" >&2
  exit 1
fi
if [[ "$LIBBOX_ID" != *.* ]]; then
  echo "error: Libbox CFBundleIdentifier '$LIBBOX_ID' must be reverse-DNS (contain '.')" >&2
  exit 1
fi
LONG_EXEC="$LIBBOX_ID"
NEW_LOAD="@rpath/Libbox.framework/${LONG_EXEC}"
NEW_ID="$NEW_LOAD"

RES_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIBBOX/Resources/Info.plist" 2>/dev/null || true)"
if [[ -z "$RES_ID" || "$RES_ID" != "$LIBBOX_ID" ]]; then
  echo "error: Libbox Resources CFBundleIdentifier '$RES_ID' != '$LIBBOX_ID' (ASC 90334)" >&2
  exit 1
fi
# ASC 90535: nested Resources must not declare CFBundleExecutable.
/usr/libexec/PlistBuddy -c 'Delete :CFBundleExecutable' "$LIBBOX/Resources/Info.plist" >/dev/null 2>&1 || true

APP_EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null || true)"
APP_BINARY=""
if [[ -n "$APP_EXEC_NAME" && -f "$APP/$APP_EXEC_NAME" ]]; then
  APP_BINARY="$APP/$APP_EXEC_NAME"
fi
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || true)"
if [[ -z "$APP_ID" ]]; then
  echo "error: app Info.plist missing CFBundleIdentifier" >&2
  exit 1
fi

APPEX="$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' -type d 2>/dev/null | head -1 || true)"
APPEX_BINARY=""
APPEX_EXEC_NAME=""
APPEX_ID=""
APPEX_ENT=""
APP_ENT="$TMP/$(basename "$APP").entitlements.plist"
if [[ -n "$APPEX" && -d "$APPEX" ]]; then
  APPEX_EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APPEX/Info.plist" 2>/dev/null || true)"
  if [[ -n "$APPEX_EXEC_NAME" && -f "$APPEX/$APPEX_EXEC_NAME" ]]; then
    APPEX_BINARY="$APPEX/$APPEX_EXEC_NAME"
  fi
  APPEX_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APPEX/Info.plist" 2>/dev/null || true)"
  if [[ -z "$APPEX_ID" ]]; then
    echo "error: appex Info.plist missing CFBundleIdentifier" >&2
    exit 1
  fi
  APPEX_ENT="$TMP/$(basename "$APPEX").entitlements.plist"
fi

# Extract entitlements WHILE signatures still exist — after --remove-signature
# codesign -d --entitlements returns nothing and we cannot re-seal NE entitlements.
if [[ ! -f "$APP/embedded.mobileprovision" ]]; then
  echo "error: missing embedded.mobileprovision in $APP" >&2
  exit 1
fi
/usr/bin/codesign -d --entitlements ":$APP_ENT" "$APP" 2>/dev/null || true
if [[ ! -f "$APP_ENT" || ! -s "$APP_ENT" ]]; then
  echo "error: could not extract entitlements from $APP before strip" >&2
  exit 1
fi
if [[ -n "$APPEX" && -d "$APPEX" ]]; then
  if [[ ! -f "$APPEX/embedded.mobileprovision" ]]; then
    echo "error: missing embedded.mobileprovision in $APPEX" >&2
    exit 1
  fi
  /usr/bin/codesign -d --entitlements ":$APPEX_ENT" "$APPEX" 2>/dev/null || true
  if [[ ! -f "$APPEX_ENT" || ! -s "$APPEX_ENT" ]]; then
    echo "error: could not extract entitlements from $APPEX before strip" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 1) Strip signatures nested-first BEFORE any rename / install_name_tool.
# ---------------------------------------------------------------------------
echo "Stripping signatures (nested first) before Mach-O rename"
# Resolve short binary path for strip (may be symlink — strip the real file after).
if [[ -L "$SHORT_BINARY" ]]; then
  REAL_PRE="$(cd "$(dirname "$SHORT_BINARY")" && /usr/bin/readlink "$SHORT_BINARY")"
  if [[ -f "$LIBBOX/$REAL_PRE" ]]; then
    remove_signature "$LIBBOX/$REAL_PRE" "Libbox.framework/$REAL_PRE"
  fi
fi
remove_signature "$SHORT_BINARY" "Libbox.framework/$(basename "$SHORT_BINARY")"
remove_signature "$LIBBOX" "Libbox.framework"
if [[ -n "$APPEX_BINARY" ]]; then
  remove_signature "$APPEX_BINARY" "PacketTunnel/$APPEX_EXEC_NAME"
fi
if [[ -n "$APPEX" && -d "$APPEX" ]]; then
  remove_signature "$APPEX" "$(basename "$APPEX")"
fi
if [[ -n "$APP_BINARY" ]]; then
  remove_signature "$APP_BINARY" "Runner/$APP_EXEC_NAME"
fi
remove_signature "$APP" "$(basename "$APP")"

# ---------------------------------------------------------------------------
# 2) Preserve the framework's canonical executable name: Libbox.
# Apple requires CFBundleExecutable to equal the framework NAME, NOT its
# reverse-DNS CFBundleIdentifier. Do not add a second Mach-O alias.
# 3) Preserve @rpath/Libbox.framework/Libbox expected by the host/appex.
# ---------------------------------------------------------------------------
BINARY="$LIBBOX/$SHORT_EXEC"
REAL_BIN=""
if [[ -e "$SHORT_BINARY" || -L "$SHORT_BINARY" ]]; then
  REAL_BIN="$(resolve_real_file "$SHORT_BINARY")"
fi
if [[ -z "$REAL_BIN" || ! -f "$REAL_BIN" ]]; then
  for cand in \
    "$LIBBOX/Versions/Current/Libbox" \
    "$LIBBOX/Versions/A/Libbox" \
    "$LIBBOX/$LIBBOX_ID"; do
    if [[ -f "$cand" ]]; then
      REAL_BIN="$(resolve_real_file "$cand")"
      break
    fi
  done
fi
if [[ -z "$REAL_BIN" || ! -f "$REAL_BIN" ]]; then
  echo "error: Libbox Mach-O missing" >&2
  exit 1
fi
assert_macho_arm64 "$REAL_BIN" "Libbox source"

# Materialize a short-name executable if the framework still uses a macOS
# Versions/ layout. A symlink is not a valid executable in this flat iOS bundle.
if [[ -L "$BINARY" || "$REAL_BIN" != "$BINARY" ]]; then
  /bin/cp -f "$REAL_BIN" "$TMP/Libbox.canonical"
  /bin/rm -f "$BINARY"
  /bin/mv -f "$TMP/Libbox.canonical" "$BINARY"
fi
# Remove historical extra executable introduced by the old resign script.
# This is the confirmed source of Apple's ITMS-90171 error.
if [[ "$LIBBOX_ID" != "$SHORT_EXEC" ]] && \
   [[ -e "$LIBBOX/$LIBBOX_ID" || -L "$LIBBOX/$LIBBOX_ID" ]]; then
  echo "Removing forbidden second Mach-O: Libbox.framework/$LIBBOX_ID"
  /bin/rm -f "$LIBBOX/$LIBBOX_ID"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $SHORT_EXEC" "$LIBBOX/Info.plist"
EXEC_NOW="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$LIBBOX/Info.plist")"
if [[ "$EXEC_NOW" != "$SHORT_EXEC" ]]; then
  echo "error: Libbox.framework CFBundleExecutable must be Libbox" >&2
  exit 1
fi
assert_macho_arm64 "$BINARY" "Libbox.framework/Libbox"

# Rebuild the install-name while the dylib is unsigned, but do NOT rewrite
# host/PacketTunnel load commands or reintroduce an executable alias.
if ! /usr/bin/install_name_tool -id "$OLD_LOAD" "$BINARY"; then
  echo "error: failed to set canonical Libbox LC_ID_DYLIB" >&2
  exit 1
fi
if [[ ! -f "$BINARY" || -L "$BINARY" ]]; then
  echo "error: Libbox framework executable must be a regular file" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 6) Re-sign nested-first with Apple Distribution + secure timestamp.
# ---------------------------------------------------------------------------
echo "Signing canonical Libbox executable with bundle ID $LIBBOX_ID"
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

resign_bundle() {
  local bundle="$1"
  local expected_id="$2"
  local ent="$3"
  # Keep embedded.mobileprovision; entitlements were saved before strip.
  if [[ ! -f "$bundle/embedded.mobileprovision" ]]; then
    echo "error: missing embedded.mobileprovision in $bundle" >&2
    exit 1
  fi
  if [[ ! -f "$ent" || ! -s "$ent" ]]; then
    echo "error: missing pre-extracted entitlements for $bundle ($ent)" >&2
    exit 1
  fi
  /usr/bin/codesign --force --sign "$IDENTITY" --identifier="$expected_id" \
    --entitlements "$ent" --generate-entitlement-der --timestamp "$bundle"
  /usr/bin/codesign --verify --verbose=4 "$bundle"
  assert_distribution_seal "$bundle" "$(basename "$bundle")"
  got="$(codesign_identifier "$bundle")"
  if [[ "$got" != "$expected_id" ]]; then
    echo "error: $bundle Identifier='$got' (want $expected_id)" >&2
    exit 1
  fi
}

if [[ -n "$APPEX" && -d "$APPEX" ]]; then
  echo "Re-signing extension $(basename "$APPEX") id=$APPEX_ID"
  resign_bundle "$APPEX" "$APPEX_ID" "$APPEX_ENT"
fi
echo "Re-signing host $(basename "$APP") id=$APP_ID"
resign_bundle "$APP" "$APP_ID" "$APP_ENT"

# ASC 90085 targets "bundle executable" — verify host + appex Mach-Os too.
if [[ -n "$APP_BINARY" && -f "$APP_BINARY" ]]; then
  assert_macho_arm64 "$APP_BINARY" "Runner/$APP_EXEC_NAME"
fi
if [[ -n "$APPEX_BINARY" && -f "$APPEX_BINARY" ]]; then
  assert_macho_arm64 "$APPEX_BINARY" "PacketTunnel/$APPEX_EXEC_NAME"
fi

OUT="$TMP/repacked.ipa"
(
  cd "$TMP"
  /usr/bin/zip -qry "$OUT" Payload
)
# Replace in place (preserve caller path).
ditto "$OUT" "$IPA"
echo "OK IPA re-signed (Libbox executable=Libbox, bundle id=$LIBBOX_ID; no executable alias)"
