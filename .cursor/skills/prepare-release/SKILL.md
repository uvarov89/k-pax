---
name: prepare-release
description: >-
  Prepare K-Pax/X-Plm for Codemagic iOS TestFlight from Windows — version,
  Info.plist/privacy, offline script tests, flutter analyze, codemagic.yaml audit.
  Use when the user says prepare release, TestFlight, Codemagic push, or /prepare-release.
---

# Prepare iOS TestFlight release (Windows)

Run only what is needed; summarize results, do not dump log walls.

## 1. Version

- Read `pubspec.yaml` `version:` (`name+build`).
- Show current value. Ask whether to bump **build** (`+N`) for a new ASC upload (duplicate `CFBundleVersion` is rejected).
- Confirm brand workflow: `ios-testflight` (K-Pax) vs `ios-testflight-xplm` (X-Plm).

## 2. iOS manifest audit (declarative)

Check without opening Xcode:

- `ios/Runner/Info.plist` / brand-applied plists — usage strings if plugins need them; `ITSAppUsesNonExemptEncryption` if present in pipeline.
- PacketTunnel entitlements / app group via `ios/scripts/apply_ios_brand.rb` outputs (or source templates under `ios/`).
- `PrivacyInfo.xcprivacy` if the change adds privacy-sensitive APIs.

## 3. Local gates

```text
python ios/scripts/test_embed_libbox_script.py
python ios/scripts/test_validate_ipa.py
flutter analyze
```

If only scripts changed, script tests may suffice; if `lib/` changed, run analyze (targeted paths OK for small diffs).

## 4. codemagic.yaml

Confirm for the target workflow:

- `xcode: latest` (or intentional pin)
- Brand env: `BUNDLE_ID`, `BUNDLE_ID_EXT`, `APP_GROUP`, `BRAND`
- Steps: `build_libbox.sh` → `apply_ios_brand.rb` → `setup_packet_tunnel.rb` → pods → signing → `flutter build ipa` → `validate_ipa.py`
- Publishing: App Store Connect integration + TestFlight

## 5. Libbox / NE sanity (do not regress)

- Libbox embeds into **Runner only**; appex must not contain `Frameworks/`.
- `validate_ipa.py` enforces host Libbox + no appex Frameworks.

## 6. Finish

- Report pass/fail checklist.
- Propose commit message; **commit/push only if the user asks**.
- Tell the user which Codemagic workflow to start after push.
