# StrawWU Release Engineering 計畫

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |
| 狀態 | 草案 |
| 對齊 | `docs/versioning.md`、`docs/iso-modes.md`、CI release workflow |

## 1. 問題陳述

現有 release-iso、preflight、VERSION bump 已存在，但缺少**可重複的正式發佈管線**：ISO 產物校驗、GPG 簽章、APT repo、deb 發佈、manifest、release notes、rollback、channel 分流。

## 2. 目標

建立 StrawWU Release Engineering（RE）管線，使 dev / nightly / beta / stable 四 channel 可預測、可審計、可回滾。

## 3. ISO Build Pipeline

| Channel | 觸發 | ISO 模式 | 壓縮 | 簽章 | 交付 |
|---------|------|----------|------|------|------|
| dev | 本地 / PR | dev-iso | zstd -l3 | 無 | 不對外 |
| nightly | cron main | dev-iso | zstd | SHA256 only | 內網 artifact |
| beta | tag `v*.*.*.*` preview | release-iso | xz | SHA256 + GPG | download + manifest |
| stable | tag `v*.*.*.0` | release-iso | xz | SHA256 + GPG | download + APT + manifest |

管線階段：`build → preflight → verify → sign → publish → notify`

## 4. Phase RE0–RE6

| Phase | 工作 | 產出 |
|-------|------|------|
| RE0 | 盤點現有 CI/release 腳本 | `docs/plans/release-baseline.json` |
| RE1 | 統一 artifact 命名 + manifest schema | `release-manifest.json` |
| RE2 | SHA256SUMS + GPG 簽章 SOP | `scripts/release-sign.sh` |
| RE3 | APT repo 結構 + strawwu-keyring | `apt.strawwu.org` |
| RE4 | package publish SOP（deb 上傳） | `scripts/publish-debs.sh` |
| RE5 | release checklist + notes 模板 | `docs/release-checklist.md` |
| RE6 | rollback policy + artifact retention | 90d nightly / ∞ stable |

## 5. APT Repository 結構

```
dists/
  noble/
    main/binary-amd64/
      Packages.gz
      Release
      Release.gpg
pool/
  main/s/strawwu-branding/strawwu-branding_0.4.0.1_amd64.deb
  ...
```

## 6. strawwu-keyring

- 套件：`strawwu-keyring` deb，安裝 `/usr/share/keyrings/strawwu-archive-keyring.gpg`
- sources.list：`deb [signed-by=...] https://apt.strawwu.org resolute main`
- 金鑰輪替：主金鑰 + 子金鑰；舊 Release 保留驗證路徑

## 7. release-manifest.json

```json
{
  "version": "0.5.0.0",
  "channel": "beta",
  "git_tag": "v0.5.0.0",
  "git_sha": "...",
  "artifacts": [
    {"name": "StrawWU-0.5.0.0-amd64.iso", "sha256": "...", "size": 0, "gpg_sig": "..."}
  ],
  "packages": [{"name": "strawwu-system", "version": "0.5.0.0"}],
  "boot_test": {"bios": "PASS", "uefi": "PASS"},
  "published_at": "ISO8601"
}
```

## 8. Release Checklist

1. `bash scripts/bump-version.sh` + CI version check PASS
2. `make preflight` ALL PASS
3. `STRAWWU_ISO_MODE=release-iso make build-iso`
4. `sha256sum -c SHA256SUMS`
5. boot-test BIOS + UEFI PASS
6. install E2E + firstboot PASS（v0.5+）
7. GPG sign ISO + manifest
8. publish APT + download CDN
9. git tag + GitHub release + HTML report hermes-deliver
10. 更新 compat-matrix / release notes

## 9. Rollback Policy

| 層級 | 觸發 | 動作 |
|------|------|------|
| ISO | boot-test FAIL 已 publish | 下架 manifest；promote 上一 stable |
| APT | 套件 regression | `apt pinning` 回上一版；hotfix tag |
| channel | beta 連續 FAIL | freeze beta；僅 dev-iso |

## 10. Artifact Retention

- dev-iso：7 天
- nightly：30 天
- beta：至下一 beta
- stable ISO + deb：永久（至少 2 major 版本）

## 11. Changelog / Release Notes 模板

- `CHANGELOG.md`：Keep a Changelog 格式
- HTML release note：hermes-deliver；含升級指引、破壞性變更、已知問題
