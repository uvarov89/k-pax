---
name: debug-codemagic
description: >-
  Diagnose Codemagic iOS/TestFlight failures from pasted logs on Windows and
  fix via scripts/plists/yaml without Xcode. Use when the user pastes a Codemagic
  log, ASC upload error, ARCHIVE FAILED, or says /debug-codemagic.
---

# Debug Codemagic iOS (from Windows)

## 1. Find the real error

- Prefer the first hard failure before `Build failed` / `ARCHIVE FAILED` / `UPLOAD FAILED`, not only the last red line.
- Classify:

| Category | Signals | Fix locus |
|----------|---------|-----------|
| Libbox / NE embed | `90205`, `90206`, Frameworks in appex, stub ~20B Libbox, sealed resource | `setup_packet_tunnel.rb`, `validate_ipa.py` |
| ASC 90171 Libbox binary | `90171` Libbox.framework/Libbox not permitted | `normalize_libbox_framework.sh` + `build_libbox.sh` (shallow dylib, Resources/Info.plist) |
| ASC Info.plist on Libbox | `90049`, `90056`, `90057`, `90360`, empty `CFBundleIdentifier` | normalize script plist keys |
| Codesign in script phase | `code object is not signed`, PhaseScriptExecution | embed sign order; no `--preserve-metadata` on unsigned |
| Signing / profiles | provisioning, team, capability | `codemagic.yaml` signing steps, bundle IDs, ASC integration |
| CocoaPods / Flutter | pod install, Swift compile | `ios/Podfile`, plugin, `pubspec` |
| Validate gate | `validate_ipa.py` AssertionError | align IPA layout with validator; do not weaken ASC rules |

## 2. Fix on Windows only

- Change `ios/scripts/*.rb|py|sh`, `Info.plist`, entitlements templates, `codemagic.yaml`, Flutter `lib/` — never “open in Xcode”.
- Re-run offline tests: `python ios/scripts/test_embed_libbox_script.py` (and validate tests).
- Bump `pubspec.yaml` build number when shipping another IPA.

## 3. Known invariants

- PacketTunnel **links** Libbox; **Runner embeds** Libbox; rpath `@executable_path/../../Frameworks`.
- Strip any `PacketTunnel.appex/Frameworks` before archive packaging.
- `validate_ipa.py` must fail if appex has `Frameworks/` or host Libbox is missing/tiny.

## 4. Output

- One-sentence root cause.
- Files changed.
- Whether user should re-run K-Pax and/or X-Plm workflow.
