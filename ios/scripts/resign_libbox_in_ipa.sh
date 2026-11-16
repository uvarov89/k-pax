#!/usr/bin/env bash
# Re-sign Libbox.framework inside an exported IPA so codesign Identifier matches
# CFBundleIdentifier after Xcode/Flutter exportArchive.
#
# exportArchive / ASC often re-stamp nested Mach-O Identifier=<basename>. Normalize
# names the binary io.nekohasekai.libbox so basename already matches; this step still
# re-seals after any export drift. Distribution IPA re-sign must keep a secure
# timestamp (disabling it breaks device install on modern iOS). Fail hard on verify.
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
EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$LIBBOX/Info.plist" 2>/dev/null || true)"
if [[ -z "$LIBBOX_ID" ]]; then
  echo "error: Libbox Info.plist missing CFBundleIdentifier" >&2
  exit 1
fi
if [[ -z "$EXEC" ]]; then
  echo "error: Libbox Info.plist missing CFBundleExecutable" >&2
  exit 1
fi
if [[ "$EXEC" != "$LIBBOX_ID" ]]; then
  echo "error: CFBundleExecutable='$EXEC' must equal CFBundleIdentifier='$LIBBOX_ID' (basename-proof)" >&2
  exit 1
fi
BINARY="$LIBBOX/$EXEC"
if [[ ! -f "$BINARY" ]]; then
  echo "error: missing $BINARY" >&2
  exit 1
fi
if [[ -f "$LIBBOX/Libbox" && "$LIBBOX/Libbox" != "$BINARY" ]]; then
  echo "error: leftover short-name Mach-O $LIBBOX/Libbox" >&2
  exit 1
fi
RES_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIBBOX/Resources/Info.plist" 2>/dev/null || true)"
if [[ -z "$RES_ID" || "$RES_ID" != "$LIBBOX_ID" ]]; then
  echo "error: Libbox Resources CFBundleIdentifier '$RES_ID' != '$LIBBOX_ID' (ASC 90334)" >&2
  exit 1
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

# Re-seal appex then host app so nested Libbox hash changes are valid.
APPEX="$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' -type d 2>/dev/null | head -1 || true)"
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
