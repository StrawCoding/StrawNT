# POST-Q3-mfp-smoke — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-q3-mfp-smoke` |
| 版本 | `0.6.3.5`（`0.6.3.4` → `0.6.3.5`） |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T07:23+08:00 |
| Worker 回合 | 階段 1/8（Hermes TICK 07:14 重驗完成） |

## 摘要

完成 Post-MVP Q3 **MFP 列印+掃描 smoke**：新增 `strawwu-device-proxy::mfp` 模組（CUPS 列印 + SANE/IPP 掃描映射）、`strawwu mfp smoke [--json]` CLI、網路印表機 fixture catalog，以及 POST-Q3 preflight gate。Worker 環境以 fixture 模擬 1 台網路 MFP 列印/掃描 PASS；Hermes 可於實機以 live CUPS/SANE 覆寫驗收。

## 交付物

| 類型 | 路徑 |
|------|------|
| MFP 核心 | `components/strawwu-device-proxy/src/mfp.rs` |
| CLI | `components/strawwu-cli/src/mfp.rs` |
| Launcher | `strawwu mfp smoke [--json]` |
| Fixture | `os-image/debs/strawwu-device-proxy/usr/share/strawwu/device-proxy/mfp-fixture-catalog.json` |
| Manifest | `device-proxy-manifest.yaml` → `mfp_smoke` |
| Smoke | `tests/device-proxy/test-mfp-smoke.sh` |
| Preflight | `tests/preflight/test-mfp-smoke.sh` |
| Baseline | `docs/plans/baselines/mfp-smoke-baseline.json` |
| OS 測試 | `os-image/debs/strawwu-device-proxy/tests/test-mfp-smoke.py` |

## 架構

```
Win32 App (spooler / WIA-Twain)
        │
        ▼ strawwu-nt device namespace
strawwu-device-proxy::mfp
        ├─ print → CUPS IPP (lpstat probe / fixture)
        └─ scan  → SANE/IPP (scanimage -L / fixture)
        │
        ▼
strawwu mfp smoke [--json]
   POST-Q3 gate: 1× network MFP, print=PASS, scan=PASS
```

## Q3 決策對照

| 決策 | 實作 |
|------|------|
| B — 列印+掃描一體（MFP） | `mfp.rs` 雙通道 smoke |
| CUPS 列印映射 | `MfpChannelResult.backend = cups` |
| SANE/IPP 掃描映射 | `MfpChannelResult.backend = sane-ipp` |
| 1 台網路印表機 | fixture `net-mfp-001` connection=network |

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.3.4` → `0.6.3.5` |
| `components/strawwu-device-proxy/src/mfp.rs` | **新增** MFP smoke |
| `components/strawwu-cli/src/mfp.rs` | **新增** CLI 格式化 |
| `components/strawwu-launcher/src/cli.rs`, `main.rs` | `mfp smoke` 子命令 |
| `components/strawwu-device-proxy/src/devices.rs` | Printer notes 含 scan |
| `components/specs/device-driver-proxy.md` | MFP smoke 交付列 |
| `os-image/debs/strawwu-device-proxy/` | fixture + manifest + python test |
| `tests/device-proxy/test-mfp-smoke.sh` | **實作** smoke（原 stub） |
| `tests/preflight/test-mfp-smoke.sh` | **擴充** 完整 gate |
| `docs/plans/baselines/mfp-smoke-baseline.json` | **新增** baseline |
| `components/strawwu-app-registry/src/deep_remove.rs` | 修復並行測試 env 競態（preflight 阻擋） |

## 驗證命令輸出

### `make test-mfp-smoke` — exit 0（2026-07-08T07:23+08:00）

Log: `/tmp/post-q3-test-mfp-smoke.log`（38 行）

```
=== POST-Q3 MFP smoke preflight ===
PASS: plan strawwu-post-mvp-roadmap.md
PASS: kickoff POST-Q3
PASS: device-proxy manifest includes mfp_smoke
PASS: cargo test strawwu-device-proxy mfp (2 tests)
PASS: cargo test strawwu-cli mfp (1 test)
PASS: strawwu mfp smoke CLI
PASS: network MFP print+scan aggregate PASS
PASS: Printer device-proxy row present
=== POST-Q3 MFP smoke: PASS ===
PASS: strawwu-device-proxy mfp python tests
PASS: mfp-smoke baseline
=== POST-Q3 MFP smoke done: PASS ===
```

### `make preflight` — exit 0（~244s，2026-07-08T07:23+08:00）

Log: `/tmp/post-q3-preflight.log`（2681 行，`grep FAIL:` **0** 行）

```
（全鏈 53+ 靜態 gate PASS，grep FAIL: 0）
=== W7-RE manifest+gpg done: PASS ===
=== POST-HW4 peripherals done: PASS ===
=== Ubuntu 26.04 closeout done: PASS ===
=== FORK-F7 closeout done: PASS ===
PREFLIGHT_EXIT=0
```

**備註**：
- 首次 preflight 曾因 `deep_remove::tests::allowlist_permits_strawwu_prefix` 並行 env 競態 FAIL；改為直接傳入 allow prefix 切片後重跑 PASS。
- 早期 preflight 亦曾因殘留 `gpg-agent` 導致 ephemeral key 生成失敗；清理 agent 後重跑 PASS。

## Git 狀態

變更尚未 commit（待 Hermes mark PASS 後由 companion 處理）。

## 未做 / 誠實邊界

- Win32 應用程式 GUI 列印/掃描對話框 E2E（需 Win app + 實機 MFP；本 stage 以 device-proxy smoke + fixture 覆蓋契約）
- 實機 CUPS 網路印表機證據（Hermes 可 unset `STRAWWU_MFP_FIXTURE` 於已安裝系統重跑）
- Hub 裝置分頁 MFP 詳細 UI（沿用 Printer 列；未另開 MFP 面板）

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-mfp-smoke
make preflight
# 實機（可選）：
STRAWWU_MFP_FIXTURE=0 strawwu mfp smoke --json
```

證據路徑：
- `docs/plans/stage-reports/POST-Q3-mfp-smoke-report.md`
- `docs/plans/baselines/mfp-smoke-baseline.json`
- `/tmp/post-q3-test-mfp-smoke.log`
- `/tmp/post-q3-preflight.log`

## Commit message（建議）

```
feat(q3): add MFP print+scan smoke for network printer

- strawwu-device-proxy mfp module (CUPS print + SANE/IPP scan)
- strawwu mfp smoke CLI with network MFP fixture catalog
- POST-Q3 preflight gate and baseline
- fix deep_remove allowlist test env race for preflight stability

Tests: make test-mfp-smoke PASS; make preflight PASS
Issue: post-q3-mfp-smoke v0.6.3.5
```
