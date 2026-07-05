# W2 Trust Baseline 階段報告

| 任務 | w2-trust-baseline |
|------|-------------------|
| 版本 | 0.4.1.9 |
| 日期 | 2026-07-05 |
| Worker | 階段 10/47（w2-trust-baseline） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

SEC2 + OBS1 + LEG2 preflight：信任鏈隱私過濾/consent、可觀測 bug bundle schema、法務隱私/EULA 草案。

## 交付物

| 類型 | 路徑 |
|------|------|
| 隱私權政策草案 | `os-image/config/branding/usr/share/strawwu/legal/privacy.html` |
| EULA 草案 | `os-image/config/branding/usr/share/strawwu/legal/eula.html` |
| SEC2 preflight | `tests/preflight/test-security-baseline.sh`（強化） |
| OBS1 preflight | `tests/preflight/test-observability.sh`（強化） |
| LEG2 preflight | `tests/preflight/test-legal-trademark.sh`（強化） |
| security baseline | `docs/plans/baselines/security-baseline.json` |
| legal baseline | `docs/plans/baselines/legal-baseline.json` |
| obs baseline | `docs/plans/baselines/obs-baseline.json`（更新） |
| Makefile | `test-security-baseline` · `test-observability` · `test-legal-trademark` · `preflight` 納入 SEC2/OBS1/LEG2 |

## 功能摘要

| Phase | 項目 | 實作 |
|-------|------|------|
| SEC2 | 隱私過濾 | `filter.py` redact password/token/SSH/home 路徑；4 項單元測試 |
| SEC2 | consent UI | GTK 上傳 checkbox 預設關；postinst `upload_opt_in=false` |
| SEC2 | 遙測清除 | W1-B1 purge 驗證 apport/whoopsie/ubuntu-report/snapd absent |
| OBS1 | bundle schema | `bundle.strawwu-bug` zip：manifest/system/journal/dmesg/logs/user-notes |
| OBS1 | CLI | `strawwu-bug-report` dry-run / create / validate |
| OBS1 | error codes | 10 項 SWU-* 碼文件化於 obs-baseline.json |
| LEG2 | privacy.html | 預設不上傳、無遙測、bug consent、opt-in 統計說明 |
| LEG2 | eula.html | 授權範圍、第三方聲明、隱私連結、商標免責 |
| LEG0 | 商標掃描 | branding overlay 無 Ubuntu UI 商標洩漏 |

## 延後範圍（遵守 deferred-scope §3）

- **不做** telemetry daemon / 匿名使用統計收集器
- **不做** 完整 opt-in 統計管線（留 w7-perf-legal-gate）
- 僅 bug consent + privacy 文案；預設關閉所有使用統計

## 驗收命令輸出（2026-07-05T03:56 UTC-4，worker 複驗）

### `make test-security-baseline` — exit 0（~2s）

Log: `/tmp/w2-trust-test-security-baseline.log`

```
=== SEC2 security-baseline done: PASS ===
```

關鍵檢查：squashfs 遙測套件 absent、filter.py/consent_gtk.py 存在、上傳預設關、4 項 privacy 單元測試 PASS、`security-baseline.json` 寫入。

### `make test-observability` — exit 0（~4s）

Log: `/tmp/w2-trust-test-observability.log`

```
=== OBS1 observability done: PASS ===
```

關鍵檢查：6 項 error code 文件化、boot-selfcheck 存在、bundle schema 7 項 entry、CLI dry-run/create/validate PASS、`obs-baseline.json` schema_ready=true。

### `make test-legal-trademark` — exit 0（~0.4s）

Log: `/tmp/w2-trust-test-legal-trademark.log`

```
=== LEG2 legal-trademark done: PASS ===
```

關鍵檢查：branding 無 Ubuntu UI 商標、privacy.html/eula.html 存在、含「預設不上傳/無遙測/opt-in」、`legal-baseline.json` 寫入。

### `make preflight` — exit 0（~33s，含 W0–W2-N1 + SEC2/OBS1/LEG2 全閘門）

Log: `/tmp/w2-trust-preflight.log`

含 W0 baseline + W1-B1 purge + W1-F1 flatpak + W1-F2 nosnap + W1-S1 initrd + W2-N1 init-tools + W2-B2 bug-reporter + W2-I1 calamares-settings + W2-R1 app-registry + **SEC2 security-baseline + OBS1 observability + LEG2 legal-trademark** 全部 exit 0。

**治本修正**：`Makefile` `preflight` target 已納入 `test-security-baseline.sh`、`test-observability.sh`、`test-legal-trademark.sh`，確保信任基線成為硬性閘門的一部分。

## 技術備註（治本）

1. **SEC2 建立在 W2-B2 之上**：本階段不複製 legacy；強化 preflight 將 W2-B2 交付物納入 SEC2 閘門，並產出 `security-baseline.json` 供後續 Wave 引用。
2. **OBS1 bundle 對齊計畫**：`.strawwu-bug` = zip；manifest 標記 `auto_upload_default=false`；journal 優先 `-u strawwu-*`。
3. **LEG2 法律文件置於 branding overlay**：隨 `apply-branding.sh` 進 rootfs/ISO；firstboot 連結留 W5-N3。
4. **遙測政策**：W1-B1 purge + 本階段 privacy/EULA 文案雙重確認「零預設上傳」。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| GPG ISO/deb 簽章 | SEC1，w7-re-manifest-gpg |
| Registry protected + polkit | SEC3 |
| compat session 權限審計 | SEC4 |
| license-inventory.csv | LEG1 |
| Calamares/GRUB/Plymouth 合規審計 | LEG3 |
| release 合規 gate CI | LEG4，w7-perf-legal-gate |
| firstboot 隱私步驟連結 EULA | W5-N3 |
| Hub「關於」法律文件入口 | W4-D3 |
| 結構化 JSON logging | OBS4 |
| release-iso 重打包 | branding 法律文件需 `make dev-iso`/`release-iso` 才進 ISO |

## VERSION

`0.4.1.8` → `0.4.1.9`（iterate）

## 建議 commit message

```
feat(w2): SEC2+OBS1+LEG2 trust/observability/legal preflight baselines

- privacy.html + eula.html draft (no default telemetry, bug consent)
- Strengthen test-security-baseline, test-observability, test-legal-trademark
- Add security-baseline.json + legal-baseline.json
- Makefile targets + preflight gate: test-security-baseline, test-observability, test-legal-trademark
Tests: make test-security-baseline PASS, make test-observability PASS,
       make test-legal-trademark PASS, make preflight PASS
Version: 0.4.1.9
```

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-security-baseline
make test-observability
make test-legal-trademark
make preflight
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| — | 待 mark |

## 下一步

**w3-d1-desktop-meta**（Hermes mark PASS 後自動啟動，勿問使用者）。
