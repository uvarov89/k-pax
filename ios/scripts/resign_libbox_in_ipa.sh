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
#    (best-effort; short-name hardlink covers loads if header has no room to grow)
# 5) Best-effort -change on unsigned host Mach-Os; hardlink/copy is the fallback
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
    echo "warn: install_name_tool -change failed on $label (no headerpad?) — short-name hardlink covers $OLD_LOAD"
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
# 2) Place Mach-O as CFBundleIdentifier; CFBundleExecutable must match.
# 3) Symlink short name → long name for existing LC_LOAD_DYLIB paths.
# ---------------------------------------------------------------------------
BINARY="$LIBBOX/$LONG_EXEC"
# Prefer the real dylib (Versions/A/Libbox) over a short symlink stub (~11B).
REAL_BIN=""
if [[ -e "$SHORT_BINARY" || -L "$SHORT_BINARY" ]]; then
  REAL_BIN="$(resolve_real_file "$SHORT_BINARY")"
fi
if [[ -z "$REAL_BIN" || ! -f "$REAL_BIN" ]]; then
  # validate_ipa-style fallbacks when root name is a text/symlink stub
  for cand in \
    "$LIBBOX/Versions/Current/Libbox" \
    "$LIBBOX/Versions/A/Libbox" \
    "$LIBBOX/$LONG_EXEC"; do
    if [[ -f "$cand" && ! -L "$cand" ]]; then
      REAL_BIN="$(resolve_real_file "$cand")"
      break
    fi
  done
fi
if [[ -z "$REAL_BIN" || ! -f "$REAL_BIN" ]]; then
  echo "error: cannot locate real Libbox Mach-O to rename" >&2
  ls -laR "$LIBBOX" >&2 || true
  exit 1
fi
assert_macho_arm64 "$REAL_BIN" "Libbox (resolved source before rename)"

if [[ "$REAL_BIN" == "$BINARY" ]]; then
  echo "Mach-O already named $LONG_EXEC"
elif [[ -f "$LIBBOX/$SHORT_EXEC" && ! -L "$LIBBOX/$SHORT_EXEC" && "$REAL_BIN" == "$(resolve_real_file "$LIBBOX/$SHORT_EXEC")" ]]; then
  echo "Renaming Mach-O $SHORT_EXEC → $LONG_EXEC"
  /bin/mv -f "$LIBBOX/$SHORT_EXEC" "$BINARY"
else
  echo "Copying resolved Mach-O → $LONG_EXEC (was symlink/Versions layout)"
  /bin/cp -f "$REAL_BIN" "$BINARY"
fi
assert_macho_arm64 "$BINARY" "Libbox.framework/$LONG_EXEC (pre-sign)"

# Short name as hard link (or copy) — NOT a symlink. Modern codesign rejects
# "the main executable or Info.plist must be a regular file (no symlinks)" when
# CFBundleExecutable / sibling load stubs are symlinks (Codemagic Xcode latest).
if [[ -e "$LIBBOX/$SHORT_EXEC" || -L "$LIBBOX/$SHORT_EXEC" ]]; then
  /bin/rm -f "$LIBBOX/$SHORT_EXEC"
fi
if /bin/ln "$BINARY" "$LIBBOX/$SHORT_EXEC" 2>/dev/null; then
  echo "Hardlink $SHORT_EXEC → $LONG_EXEC (codesign-safe; covers $OLD_LOAD)"
else
  /bin/cp -f "$BINARY" "$LIBBOX/$SHORT_EXEC"
  echo "Copied $SHORT_EXEC from $LONG_EXEC (hardlink unavailable; covers $OLD_LOAD)"
fi

# Info.plist must be a regular file too (Versions layouts sometimes symlink it).
if [[ -L "$LIBBOX/Info.plist" ]]; then
  plist_real="$(resolve_real_file "$LIBBOX/Info.plist")"
  /bin/rm -f "$LIBBOX/Info.plist"
  /bin/cp -f "$plist_real" "$LIBBOX/Info.plist"
  echo "Materialized Libbox Info.plist (was symlink → $plist_real)"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $LONG_EXEC" "$LIBBOX/Info.plist"
EXEC_NOW="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$LIBBOX/Info.plist")"
if [[ "$EXEC_NOW" != "$LONG_EXEC" || "$EXEC_NOW" != "$LIBBOX_ID" ]]; then
  echo "error: CFBundleExecutable='$EXEC_NOW' must equal CFBundleIdentifier='$LIBBOX_ID'" >&2
  exit 1
fi
if [[ -L "$BINARY" || -L "$LIBBOX/Info.plist" ]]; then
  echo "error: CFBundleExecutable or Info.plist is still a symlink — codesign will fail" >&2
  ls -la "$LIBBOX" >&2 || true
  exit 1
fi

assert_macho_arm64 "$BINARY" "Libbox.framework/$LONG_EXEC (pre-sign)"

# ---------------------------------------------------------------------------
# 4) -id on unsigned Libbox; 5) best-effort -change on unsigned hosts.
# ---------------------------------------------------------------------------
if /usr/bin/install_name_tool -id "$NEW_ID" "$BINARY" 2>/dev/null; then
  echo "OK install_name_tool -id $NEW_ID"
else
  echo "warn: install_name_tool -id could not lengthen to $NEW_ID — keeping prior id; short-name hardlink covers loads"
fi

if [[ -n "$APP_BINARY" ]]; then
  try_change_load "$APP_BINARY" "Runner/$APP_EXEC_NAME" "$NEW_LOAD"
fi
if [[ -n "$APPEX_BINARY" ]]; then
  try_change_load "$APPEX_BINARY" "PacketTunnel/$APPEX_EXEC_NAME" "$NEW_LOAD"
fi
# Any other Mach-O under the app that still loads the short path.
# Prefer short-name hardlink fallback over aggressive -change; scan PlugIns + Frameworks.
for candidate in \
  "$APP_BINARY" \
  "$APPEX_BINARY" \
  "$APP"/Frameworks/*/* \
  "$APP"/PlugIns/*/*; do
  [[ -n "$candidate" && -f "$candidate" && ! -L "$candidate" ]] || continue
  case "$candidate" in
    "$BINARY"|"$LIBBOX"/*) continue ;;
  esac
  if macho_loads_libbox "$candidate"; then
    try_change_load "$candidate" "${candidate#"$APP"/}" "$NEW_LOAD"
  fi
done

# ---------------------------------------------------------------------------
# 6) Re-sign nested-first with Apple Distribution + secure timestamp.
# ---------------------------------------------------------------------------
echo "Stamping Libbox Identifier=$LIBBOX_ID (Mach-O basename=$LONG_EXEC)"
/usr/bin/codesign --force --sign "$IDENTITY" --identifier="$LIBBOX_ID" --timestamp "$BINARY"
# Prefer non-deep framework seal; --deep used to retry and still fail on symlinks.
if ! /usr/bin/codesign --force --sign "$IDENTITY" --identifier="$LIBBOX_ID" --timestamp --generate-entitlement-der "$LIBBOX"; then
  echo "warn: framework codesign without --deep failed; retry once"
  /usr/bin/codesign --force --sign "$IDENTITY" --identifier="$LIBBOX_ID" --timestamp "$LIBBOX"
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

assert_macho_arm64 "$BINARY" "Libbox.framework/$LONG_EXEC (post-sign)"

# ---------------------------------------------------------------------------
# 6b) Re-sign EVERY embedded Runner framework with Apple Distribution.
# Stripping Runner.app invalidates nested seals; Libbox alone is not enough.
# ASC 90034: sing_box.framework (org.cocoapods.sing-box) must use submission cert.
# ---------------------------------------------------------------------------
resign_embedded_framework() {
  local fw="$1"
  local label
  label="$(basename "$fw")"
  local plist="$fw/Info.plist"
  if [[ ! -f "$plist" ]]; then
    echo "error: $label missing Info.plist" >&2
    exit 1
  fi
  local fid fexec
  fid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  fexec="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
  if [[ -z "$fid" ]]; then
    echo "error: $label missing CFBundleIdentifier" >&2
    exit 1
  fi
  if [[ -n "$fexec" ]]; then
    local bin="$fw/$fexec"
    if [[ -f "$bin" || -L "$bin" ]]; then
      remove_signature "$bin" "$label/$fexec"
      /usr/bin/codesign --force --sign "$IDENTITY" --identifier="$fid" --timestamp "$bin"
    fi
  fi
  remove_signature "$fw" "$label"
  /usr/bin/codesign --force --sign "$IDENTITY" --identifier="$fid" \
    --timestamp --generate-entitlement-der "$fw" \
    || /usr/bin/codesign --force --sign "$IDENTITY" --identifier="$fid" --timestamp "$fw"
  /usr/bin/codesign --verify --verbose=4 "$fw"
  assert_distribution_seal "$fw" "$label"
  got="$(codesign_identifier "$fw")"
  if [[ "$got" != "$fid" ]]; then
    echo "error: $label Identifier='$got' (want $fid) — ASC 90034 risk" >&2
    exit 1
  fi
  echo "Embedded framework sealed: $label ($fid)"
}

if [[ -d "$APP/Frameworks" ]]; then
  shopt -s nullglob
  for fw in "$APP"/Frameworks/*.framework; do
    [[ -d "$fw" ]] || continue
    if [[ "$(basename "$fw")" == "Libbox.framework" ]]; then
      echo "Skip Libbox.framework (already Distribution-sealed)"
      continue
    fi
    echo "Re-signing embedded framework $(basename "$fw") (ASC 90034)"
    resign_embedded_framework "$fw"
  done
  shopt -u nullglob
fi

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
echo "OK IPA re-signed (Libbox id=$LIBBOX_ID exec=$LONG_EXEC short=$SHORT_EXEC; embedded frameworks Distribution-sealed)"
