#!/usr/bin/env bash
# Re-sign Libbox.framework inside an exported IPA so codesign Identifier matches
# CFBundleIdentifier after Xcode/Flutter exportArchive.
#
# Build/link keep Mach-O basename "Libbox" so `-framework Libbox` works. After
# exportArchive, rename the binary to CFBundleIdentifier (io.nekohasekai.libbox),
# update CFBundleExecutable + install names, then re-seal — so ASC/device
# Identifier=<basename> cannot diverge from the plist (ASC 90334 / Unable to Install).
# Distribution IPA re-sign must keep a secure timestamp. Fail hard on verify.
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

set_plist_string() {
  local plist="$1" key="$2" val="$3"
  local pb=/usr/libexec/PlistBuddy
  if $pb -c "Print :$key" "$plist" >/dev/null 2>&1; then
    $pb -c "Set :$key $val" "$plist"
  else
    $pb -c "Add :$key string $val" "$plist"
  fi
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
if [[ ! -d "$LIBBOX" ]]; then
  echo "error: missing $LIBBOX" >&2
  exit 1
fi

LIBBOX_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIBBOX/Info.plist" 2>/dev/null || true)"
if [[ -z "$LIBBOX_ID" ]]; then
  echo "error: Libbox Info.plist missing CFBundleIdentifier" >&2
  exit 1
fi
RES_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIBBOX/Resources/Info.plist" 2>/dev/null || true)"
if [[ -z "$RES_ID" || "$RES_ID" != "$LIBBOX_ID" ]]; then
  echo "error: Libbox Resources CFBundleIdentifier '$RES_ID' != '$LIBBOX_ID' (ASC 90334)" >&2
  exit 1
fi

OLD_LOAD="@rpath/Libbox.framework/Libbox"
NEW_LOAD="@rpath/Libbox.framework/${LIBBOX_ID}"

# Build leaves short-name Mach-O; locate it (or already-renamed binary on re-run).
BINARY=""
if [[ -f "$LIBBOX/$LIBBOX_ID" ]]; then
  BINARY="$LIBBOX/$LIBBOX_ID"
elif [[ -f "$LIBBOX/Libbox" ]]; then
  BINARY="$LIBBOX/Libbox"
else
  echo "error: missing Libbox Mach-O under $LIBBOX" >&2
  ls -la "$LIBBOX" >&2 || true
  exit 1
fi

# Basename-proof rename: codesign Identifier=<basename> must equal CFBundleIdentifier.
if [[ "$(basename "$BINARY")" != "$LIBBOX_ID" ]]; then
  echo "Renaming Mach-O $(basename "$BINARY") → $LIBBOX_ID (post-export basename-proof)"
  mv "$BINARY" "$LIBBOX/$LIBBOX_ID"
  BINARY="$LIBBOX/$LIBBOX_ID"
fi
if [[ -f "$LIBBOX/Libbox" && "$LIBBOX/Libbox" != "$BINARY" ]]; then
  echo "error: leftover short-name Mach-O $LIBBOX/Libbox" >&2
  exit 1
fi

set_plist_string "$LIBBOX/Info.plist" CFBundleExecutable "$LIBBOX_ID"
EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$LIBBOX/Info.plist" 2>/dev/null || true)"
if [[ "$EXEC" != "$LIBBOX_ID" ]]; then
  echo "error: CFBundleExecutable='$EXEC' must equal CFBundleIdentifier='$LIBBOX_ID' (basename-proof)" >&2
  exit 1
fi

/usr/bin/install_name_tool -id "$NEW_LOAD" "$BINARY" 2>/dev/null || true

# Rewrite LC_LOAD_DYLIB in host + appex so runtime still finds the renamed binary.
rewrite_load() {
  local bin="$1"
  [[ -f "$bin" ]] || return 0
  if otool -L "$bin" 2>/dev/null | grep -q "$OLD_LOAD"; then
    echo "Rewriting LC_LOAD_DYLIB in $(basename "$bin"): Libbox → $LIBBOX_ID"
    /usr/bin/install_name_tool -change "$OLD_LOAD" "$NEW_LOAD" "$bin"
  fi
}

APP_EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null || true)"
if [[ -n "$APP_EXEC" && -f "$APP/$APP_EXEC" ]]; then
  rewrite_load "$APP/$APP_EXEC"
fi
APPEX="$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' -type d 2>/dev/null | head -1 || true)"
if [[ -n "$APPEX" && -d "$APPEX" ]]; then
  APPEX_EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APPEX/Info.plist" 2>/dev/null || true)"
  if [[ -n "$APPEX_EXEC" && -f "$APPEX/$APPEX_EXEC" ]]; then
    rewrite_load "$APPEX/$APPEX_EXEC"
  fi
fi

echo "Stamping Libbox Identifier=$LIBBOX_ID (bundle + Mach-O $EXEC)"
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
done

# Re-seal appex then host app so nested Libbox hash / load-path changes are valid.
resign_bundle() {
  local bundle="$1"
  local ent="$TMP/$(basename "$bundle").entitlements.plist"
  /usr/bin/codesign -d --entitlements ":$ent" "$bundle" 2>/dev/null || true
  if [[ -f "$ent" && -s "$ent" ]]; then
    /usr/bin/codesign --force --sign "$IDENTITY" --entitlements "$ent" \
      --generate-entitlement-der --timestamp "$bundle"
  else
    /usr/bin/codesign --force --sign "$IDENTITY" \
      --generate-entitlement-der --timestamp "$bundle"
  fi
  /usr/bin/codesign --verify --verbose=4 "$bundle"
}

if [[ -n "$APPEX" && -d "$APPEX" ]]; then
  echo "Re-signing extension $(basename "$APPEX")"
  resign_bundle "$APPEX"
fi
echo "Re-signing host $(basename "$APP")"
resign_bundle "$APP"

OUT="$TMP/repacked.ipa"
(
  cd "$TMP"
  /usr/bin/zip -qry "$OUT" Payload
)
# Replace in place (preserve caller path).
ditto "$OUT" "$IPA"
echo "OK Libbox re-signed in IPA (id $LIBBOX_ID, exec $EXEC)"
