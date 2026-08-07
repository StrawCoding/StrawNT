# StrawNT Win32 IPC Interop Platform (NTW4)

**Status:** product spec (stage `ntw4-win32-ipc`)  
**Product:** StrawNT  
**Backend:** `execution_backend=wine` · `engine=proton-ge` · **powered by Wine**  
**Scene:** 防作弊 App ↔ 遊戲（demo fixtures；非官方反作弊認證）

---

## 1. Goal

Provide a **Win32 IPC interop bus** so a companion / anti-cheat-style App and a game can exchange messages:

| Boundary | Transport | Default policy |
|----------|-----------|----------------|
| **same_prefix** | Native Wine Win32 IPC subset (named pipes first) | Allowed within one `WINEPREFIX` |
| **cross_prefix** | Host broker `strawnt-interopd` proxy | **Default deny**; requires capability grant |

This is an **interop platform**, not a ranked / online anti-cheat pass claim.

---

## 2. Non-goals (honesty)

- Do **not** claim Easy Anti-Cheat / BattlEye / Vanguard / any vendor online ranked PASS.
- Do **not** claim full Windows kernel object semantics or arbitrary COM.
- Do **not** load Windows `.sys` into the Linux kernel.
- Demo fixtures (`strawnt_ac_stub.exe`, `strawnt_game_stub.exe`) prove **message exchange only**.

Matrix rows for real AC stacks remain **PARTIAL** / **UNKNOWN** until independently proven.

---

## 3. Supported Win32 IPC subset (same_prefix)

Inside a single StrawNT Wine prefix (vendored Proton-GE):

| Mechanism | Support in NTW4 | Notes |
|-----------|-----------------|-------|
| Named pipes (`\\.\pipe\…`) | **Yes** (primary) | CreateNamedPipe / CreateFile + Read/Write |
| Window messages (`PostMessage` / `SendMessage`) | Documented only | Future; not required for NTW4 smoke |
| Shared section / file mapping | Documented only | Future |
| Local RPC / ALPC | Out of scope | |
| COM | Optional later | Not NTW4 gate |

Same-prefix traffic stays inside Wine’s object namespace for that prefix (no host broker required).

---

## 4. Cross-prefix: host broker

Wine named objects do **not** span prefixes. Cross-prefix uses a Linux host broker:

```
┌──────────────┐     TCP 127.0.0.1      ┌──────────────────┐     TCP 127.0.0.1      ┌──────────────┐
│ AC stub PE   │ ─────────────────────► │ strawnt-interopd │ ◄──────────────────── │ Game stub PE │
│ prefix=ac-*  │   AUTH+RECV/SEND       │  capability map  │   AUTH+SEND/RECV      │ prefix=game-*│
└──────────────┘                        └──────────────────┘                        └──────────────┘
```

### 4.1 Components

| Component | Path / binary | Role |
|-----------|---------------|------|
| Spec | `docs/specs/interop-win32-ipc.md` | This document |
| Library + smoke | `components/strawnt-interop/` | Grant store, broker, smoke orchestration |
| Daemon | `strawnt-interopd` | TCP listen + route |
| CLI | `strawnt interop …` | grant / smoke / status |
| Fixtures | `components/strawnt-interop/fixtures/` | Two MinGW PE stubs |

### 4.2 Wire protocol (line-oriented ASCII, `\n` terminated)

Client → broker:

```text
AUTH <token> <prefix_id> <role> <channel>
SEND <payload>
RECV <timeout_ms>
QUIT
```

Broker → client:

```text
OK AUTH
OK SEND
DATA <payload>
ERR <reason>
```

- `payload`: single-line printable ASCII, max 4096 bytes (no embedded newlines).
- `role`: `ac` | `game` | `peer` (informational; authorization is token+prefix+channel).
- Bind: `127.0.0.1` only (loopback). Default port `17864` (`STRAWNT_INTEROP_PORT` override).

### 4.3 Capability grants (default deny)

A grant is a tuple:

```text
token × channel × allowed_prefix_ids[]
```

Rules:

1. No grant → every `AUTH` fails (`ERR deny`).
2. `AUTH` succeeds only if `token` exists, `channel` matches, and `prefix_id` ∈ allowed set.
3. Messages are queued per `channel` (FIFO). Only authenticated sessions for that channel may `SEND`/`RECV`.
4. App Manager (NTW5+) is the intended long-term grant issuer; NTW4 exposes `strawnt interop grant` for smoke / ops.

Revocation: drop token from the grant map (broker restart clears ephemeral grants unless loaded from a grant file).

---

## 5. Security model

| Control | Behavior |
|---------|----------|
| Cross-prefix default | Deny |
| Bind address | Loopback only |
| Capability token | Opaque string; treat as secret |
| Ranked / vendor AC | Never implied by successful IPC |
| Logging | No secrets in PASS evidence JSON |

Future (not NTW4 gate): Unix peer credentials, App Manager permission UI, per-app sandbox profiles.

---

## 6. Demo fixtures

| PE | Role | Modes |
|----|------|-------|
| `strawnt_ac_stub.exe` | Anti-cheat companion stand-in | `pipe` listen/recv; `broker` AUTH+RECV/SEND |
| `strawnt_game_stub.exe` | Game stand-in | `pipe` connect/send; `broker` AUTH+SEND/RECV |

Smoke markers (examples):

- Same-prefix pipe payload: `STRAWNT_NTW4_SAME`
- Cross-prefix broker payload: `STRAWNT_NTW4_CROSS`

---

## 7. CLI surface

```text
strawnt interop status [--json]
strawnt interop grant --token T --channel C --prefix A --prefix B [--json]
strawnt interop smoke [--home DIR] [--json]
```

`interop smoke` must:

1. Build fixtures if missing (MinGW).
2. Prove **same_prefix** named-pipe exchange.
3. Start broker, grant channel, prove **cross_prefix** exchange.
4. Emit evidence with `ranked_pass_claimed=false`.

---

## 8. Acceptance evidence

| Artifact | Requirement |
|----------|-------------|
| `docs/specs/interop-win32-ipc.md` | Present (this file) |
| `tests/strawnt/output/ntw4-interop.json` | Top-level `status=PASS` |
| Claims | `same_prefix=true`, `cross_prefix=true` |
| Honesty | `claims.ranked_pass_claimed == false` |
| Simulation | `simulated != true` for PASS |

Harness: `tests/strawnt/ntw4-interop.sh` (Make: `test-strawnt-ntw4-interop`).

---

## 9. Relation to later stages

- **NTW5 App Manager** owns install/list/launch and will issue interop capability grants from permissions.
- **NTW6 sysapps** may surface grant UI in `settings` / `compat_center`.
- Golden apps (`line.exe`, `steam.exe`) are **not** AC ranked gates; IPC PASS here does not upgrade their matrix to ranked PASS.
