# W7-RE apt-repo 階段報告

| 任務 | w7-re-apt-repo |
|------|----------------|
| 版本 | 0.5.0.1 |
| 日期 | 2026-07-06 |
| Worker | 階段 39/47（w7-re-apt-repo） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

建立 **strawwu APT repository** 結構（RE3）與 **`strawwu-keyring` deb** + **`publish-debs.sh`** 發佈管線（RE4），對齊 `strawwu-release-engineering-plan.md` stable channel APT 交付需求。

## 交付物

| 類型 | 路徑 |
|------|------|
| Keyring 套件 | `os-image/debs/strawwu-keyring/` |
| 測試用公鑰 | `os-image/debs/strawwu-keyring/keys/strawwu-archive-test.pub` |
| APT 發佈腳本 | `scripts/publish-debs.sh` |
| Schema 驗證 | `tests/apt-repo/validate-apt-repo.py` |
| Preflight gate | `tests/preflight/test-apt-repo.sh` |
| baseline JSON | `docs/plans/baselines/apt-repo-baseline.json` |
| Makefile | `test-apt-repo`、`publish-debs`；`preflight` 含本階段 |
| target-manifest | `strawwu-keyring` 列為 Calamares 首個 staged deb |

## 功能摘要

| 元件 | 說明 |
|------|------|
| **strawwu-keyring** | 安裝 `/usr/share/keyrings/strawwu-archive-keyring.gpg`；支援 `STRAWWU_KEYRING_GPG` / `STRAWWU_GPG_KEY_ID` 或內建測試公鑰 |
| **publish-debs.sh** | 從 `os-image/debs/*/output` + `packaging/output` 收集版本對應 `.deb` → `pool/` + `dists/noble/main/binary-amd64/{Packages.gz,Release,Release.gpg}` |
| **簽章模式** | 沿用 `STRAWWU_RELEASE_SIGN_MODE`（auto/required/skip）與 `STRAWWU_GPG_KEY_ID`；與 RE2 `release-sign.sh` 一致 |
| **sources 對齊** | branding `strawwu.sources` 已指向 keyring 路徑；target-manifest 安裝 keyring 於其他 strawwu deb 之前 |

### APT repo 結構（摘要）

```
dists/noble/
  Release
  Release.gpg
  main/binary-amd64/
    Packages.gz
pool/main/{letter}/{package}/*.deb
```

## 驗收命令輸出

### `make test-apt-repo` — exit 0

Log: `/tmp/w7-re-test-apt-repo.log`

```
=== W7-RE apt-repo preflight ===
（全項 PASS，含 ephemeral GPG sign/verify、keyring deb、publish-debs 管線）
=== W7-RE apt-repo done: PASS ===
```

### `make preflight` — exit 0（~226s，2124 行）

Log: `/tmp/w7-re-preflight.log`

含 W0–W6 全部階段 + W7-RE manifest+gpg + **W7-RE apt-repo** 終行：`=== W7-RE apt-repo done: PASS ===`

補充：`tests/preflight/test-release-baseline.sh` 執行後 `release-baseline.json` 已更新 `apt_repo_ready: true`、`publish_debs` 腳本路徑與 `W7-RE3` gap 標記。

## 變更檔案清單

```
VERSION (0.5.0.0 → 0.5.0.1)
Makefile
scripts/publish-debs.sh                                           (新增)
os-image/debs/strawwu-keyring/debian/control                      (新增)
os-image/debs/strawwu-keyring/build-deb.sh                        (新增)
os-image/debs/strawwu-keyring/keys/strawwu-archive-test.pub       (新增，僅公鑰)
tests/apt-repo/validate-apt-repo.py                               (新增)
tests/preflight/test-apt-repo.sh                                  (新增)
tests/preflight/test-release-manifest.sh                          (gaps_closed 更新)
tests/preflight/test-security-baseline.sh                         (apt_signing 區塊)
tests/preflight/test-release-baseline.sh                          (apt_repo_ready 偵測)
docs/plans/baselines/release-baseline.json                        (apt_repo_ready: true)
os-image/debs/strawwu-target-setup/.../target-manifest.yaml       (strawwu-keyring)
docs/plans/baselines/apt-repo-baseline.json                       (新增)
docs/plans/baselines/release-manifest-baseline.json               (preflight 更新)
docs/plans/baselines/security-baseline.json                       (preflight 更新)
docs/plans/stage-reports/W7-RE-apt-repo-report.md                 (本檔)
```

## 技術備註（治本）

1. **單一簽章策略**：APT `Release.gpg` 與 ISO `SHA256SUMS.asc` 共用 `STRAWWU_GPG_KEY_ID` / auto-detect 邏輯，降低 release 管線認知負擔。
2. **無生產金鑰可測**：內建 `strawwu-archive-test.pub` 供 preflight/CI 建 keyring deb；隔離測試以 ephemeral `apt@test.strawwu.local` 驗證完整 sign→verify。
3. **版本過濾**：`publish-debs.sh` 僅納入 `_${VERSION}_` 的 deb，避免多版本 output 污染 repo。
4. **安裝順序**：`target-manifest.yaml` 將 `strawwu-keyring` 置首，確保 `strawwu.sources` 的 `Signed-By` 在 apt update 前可用。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| CI `release.yml` GPG secret 注入 | w7-ci-nightly |
| 生產 StrawWU archive 簽章金鑰部署 | 基礎設施（非本 stage） |
| `strawwu-apt` GitHub Pages 自動觸發 | 已有 `release.yml` dispatch；待 nightly CI 串接 |
| 全量 deb publish（22+ 套件） | 待 release tag 時 `make publish-debs` |

## VERSION

`0.5.0.0` → `0.5.0.1`（`bash scripts/bump-version.sh iterate`）

## 建議 commit message

```
feat(w7): add APT repo pipeline and strawwu-keyring deb

- RE3: strawwu-keyring deb + dists/pool APT layout
- RE4: scripts/publish-debs.sh (Packages.gz + Release.gpg)
- Preflight gate test-apt-repo + apt-repo-baseline.json
- target-manifest: install keyring before other strawwu debs
- VERSION 0.5.0.1
Tests: make test-apt-repo PASS; make preflight PASS
```

## 下一階段

**w7-ci-nightly**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-apt-repo
make preflight
```
