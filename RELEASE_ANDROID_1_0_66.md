# Android hotfix 1.0.66

Includes fix for K-Pax / X-Plm in-app APK downloads through GitHub asset CDN redirects and a browser fallback. No change to VPN servers, subscriptions, or payment logic.

From a Windows development machine with the **existing original** Android signing keystore and `android/key.properties`, installed Flutter and authenticated GitHub CLI:

```powershell
cd C:\GitHub\antirkn_vpn
git fetch origin
git switch release/android-1.0.66
powershell -ExecutionPolicy Bypass -File .\scripts\publish-android-1.0.66.ps1 -SkipPublish
```

After validating APK on an Android 16 phone, run the same command without `-SkipPublish` to publish the original-key signed K-Pax and X-Plm releases. The script checks certificate SHA-256 parity against the published 1.0.65 APKs before any publication. Do not upload signing passwords or keystore into the public repository.

The backend `/app/android` endpoints need to advertise the new tag after publishing. Existing clients with broken CDN redirect handling must first update from a browser; do not uninstall them. Users who installed 1.0.65 by browser will receive the 1.0.66 update through the still-broken 1.0.65 updater only if its code was already fixed; otherwise use browser again once.
