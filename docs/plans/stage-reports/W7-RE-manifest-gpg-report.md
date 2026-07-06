# W7-RE manifest+gpg 階段報告

| 任務 | w7-re-manifest-gpg |
|------|-------------------|
| 版本 | 0.5.0.0 |
| 日期 | 2026-07-06 |
| Worker | 階段 38/47（w7-re-manifest-gpg） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

建立可重複的 **release-manifest.json** 產生器（RE1）與 **SHA256SUMS + detached GPG** 簽章管線（RE2），對齊 `strawwu-release-engineering-plan.md` beta/stable channel 交付需求。

## 交付物

| 類型 | 路徑 |
|------|------|
| Manifest 產生器 | `scripts/generate-release-manifest.sh` |
| GPG 簽章腳本 | `scripts/release-sign.sh` |
| Schema 驗證 | `tests/release-manifest/validate-release-manifest.py` |
| Preflight gate | `tests/preflight/test-release-manifest.sh` |
| baseline JSON | `docs/plans/baselines/release-manifest-baseline.json` |
| 產物範例 | `os-image/output/release-manifest.json` |
| Makefile | `generate-release-manifest`、`release-sign`、`test-release-manifest`；`preflight` 含本階段 |

## 功能摘要

| 元件 | 說明 |
|------|------|
| **generate-release-manifest.sh** | 依 `VERSION` 產生 `strawwu-release-manifest/v1` JSON：git sha/tag、channel（preview→beta / d=0→stable）、ISO artifact（sha256+size+gpg_sig）、22 個 strawwu deb 套件清單、boot_test 狀態、checksums 中繼資料 |
| **release-sign.sh** | 產生 `SHA256SUMS`；`auto`/`required`/`skip` 三模式 GPG detached 簽章（`*.asc`）；簽章後自動更新 manifest |
| **效能** | 優先讀取既有 `SHA256SUMS` 避免重算 6GB ISO；預設僅納入版本對應或最新單一 ISO（非全量掃描） |
| **validate-release-manifest.py** | 驗證 schema、channel、artifact sha256、packages、published_at |
| **隔離測試** | 以 stub ISO + ephemeral `StrawWU Test Release` GPG 金鑰驗證完整 sign→verify 管線 |

### release-manifest.json schema（摘要）

```json
{
  "schema": "strawwu-release-manifest/v1",
  "version": "0.5.0.0",
  "channel": "stable|beta",
  "git_tag": "v0.5.0.0",
  "git_sha": "...",
  "artifacts": [{"name": "StrawWU-….iso", "sha256": "…", "size": 0, "gpg_sig": "….asc"}],
  "packages": [{"name": "strawwu-…", "version": "0.5.0.0"}],
  "boot_test": {"bios": "PENDING|PASS", "uefi": "PENDING|PASS"},
  "checksums": {"file": "SHA256SUMS", "gpg_sig": "SHA256SUMS.asc"},
  "published_at": "ISO8601Z"
}
```

## 驗收命令輸出

### `make test-release-manifest` — exit 0

Log: `/tmp/w7-re-test-release-manifest.log`

```
=== W7-RE manifest+gpg preflight ===
（全項 PASS，含 ephemeral GPG sign/verify、stub ISO manifest、repo output manifest）
=== W7-RE manifest+gpg done: PASS ===
```

### `make preflight` — exit 0（~321s）

Log: `/tmp/w7-re-preflight.log`

含 W0–W6 全部階段 + **W7-RE manifest+gpg** 終行：`=== W7-RE manifest+gpg done: PASS ===`

## 變更檔案清單

```
VERSION (0.4.1.41 → 0.5.0.0)
Makefile
scripts/generate-release-manifest.sh                           (新增)
scripts/release-sign.sh                                        (新增)
tests/release-manifest/validate-release-manifest.py            (新增)
tests/preflight/test-release-manifest.sh                       (新增)
tests/preflight/test-security-baseline.sh                      (SEC1 移至 release_signing)
tests/preflight/test-release-baseline.sh                       (RE1/RE2 gaps 更新)
docs/plans/baselines/release-manifest-baseline.json            (新增)
docs/plans/stage-reports/W7-RE-manifest-gpg-report.md          (本檔)
os-image/output/release-manifest.json                          (generate 產物，不 commit)
```

## 技術備註（治本）

1. **單一入口**：`release-sign.sh` 完成 checksum + GPG 後呼叫 `generate-release-manifest.sh`，避免 manifest 與簽章不同步。
2. **無金鑰降級**：`STRAWWU_RELEASE_SIGN_MODE=auto`（預設）在無 StrawWU 生產金鑰時仍產 SHA256SUMS 並警告，不阻斷 dev/nightly；正式發佈設 `required`。
3. **不 hash 全庫 ISO**：解決多版本 ISO 共存時 preflight 卡死問題；正式 tag 發佈時以 `StrawWU-${VERSION}-amd64.iso` 為準。
4. **GPG 偵測**：`STRAWWU_GPG_KEY_ID` 或 uid 含 `strawwu` 的 secret key；測試以 `release@test.strawwu.local` 隔離驗證。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| APT repo + `strawwu-keyring` deb | w7-re-apt-repo |
| `publish-debs.sh` / Release.gpg | w7-re-apt-repo |
| CI `release.yml` GPG secret 注入 | 待 w7-ci-nightly 或 Hermes 部署 |
| 生產 StrawWU release 金鑰 | 基礎設施（非本 stage） |
| `os-image/output/release-manifest.json` 中 artifact 為舊版 ISO | 待 `release-iso` 打 0.5.0.0 後更新 |

## VERSION

`0.4.1.41` → `0.5.0.0`（`bash scripts/bump-version.sh minor`，Wave 7 RE 里程碑）

## 建議 commit message

```
feat(w7): add release-manifest generator and GPG signing pipeline

- RE1: scripts/generate-release-manifest.sh (strawwu-release-manifest/v1)
- RE2: scripts/release-sign.sh (SHA256SUMS + detached GPG)
- Preflight gate test-release-manifest + baseline JSON
- VERSION 0.5.0.0 (Wave 7 RE milestone)
Tests: make test-release-manifest PASS; make preflight PASS
```

## 下一階段

**w7-re-apt-repo**（Hermes mark PASS 後自動啟動，勿問使用者）。
