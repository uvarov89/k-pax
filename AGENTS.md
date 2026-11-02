# K-Pax (pulse_vpn)

Flutter VPN client + server ops for k-pax.space. Site frontend is **not** in this repo.

## Core

- No commits / pushes / force-git without explicit ask.
- Do not run long test suites or full platform builds unless asked; prefer targeted `dart test path` / analyze.
- Prefer SOLID, no data races; match existing style in the touched file.
- Quality first: token limits never justify guessing or shipping broken fixes.

## Architecture (short)

| Area | Path | Role |
|------|------|------|
| App UI / state | `lib/` | Flutter client (Provider, features/) |
| Tunnel / sub / updates | `lib/core/services/` | sing-box, subscription, deep links, updates |
| Screens | `lib/features/` | home, account, paywall, settings, locations |
| Theme / l10n | `lib/app/` | Nord/K-Pax theme, strings |
| Android / iOS / Windows | `android/`, `ios/`, `windows/` | Platform shells, installer, PacketTunnel |
| Server / panel | `server/` | Caddy, panel.py, watch/limit/backup, x-plm |
| Ops docs | `docs/` | runbook, iOS/TestFlight, Cloudflare |
| Vendored | `third_party/` | sing-box / secure storage forks — read only when task needs it |

Canonical map (keep short): `.cursor/project-source-index.txt`

## Token workflow

1. **A — find:** Grep/Glob with a narrow path. Do not walk the whole workspace or `third_party/` without a reason.
2. **B — read:** Open only the files (and line ranges) needed. Do not re-read an unchanged file in the same turn/session.
3. If the target path is unclear after one focused search, ask which area (client / server / windows / ios) instead of broad exploration.
