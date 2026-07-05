# StrawWU Wave 0→8 全自動鎖序

| 項目 | 值 |
|------|-----|
| 總 stage 數 | **47** |
| 起點 | `w0-baseline` |
| 終點 | `w8-mvp-closeout` |
| 接續腳本 | `longtask_wave_transition_next.sh` |
| 路由 | `longtask_transition_dispatch.sh`（wave vs phase） |
| 全 PASS 驗證 | `make test-wave-all-pass` |

## 鎖序（47 段）

```
w0-baseline
→ w1-b1-purge → w1-f1-flathub → w1-f2-nosnap → w1-s1-initrd
→ w2-b2-bug-reporter → w2-i1-calamares-settings → w2-r1-app-registry → w2-n1-initd → w2-trust-baseline
→ w3-d1-desktop-meta → w3-i2-live-ux → w3-b3-update-notifier → w3-n2-target-setup → w3-w0-wincompat-baseline
→ w4-d2-strawwu-shell → w4-d3-hub-settings → w4-r2-apps-page → w4-f3-flathub-hub → w4-w1-registry-launcher → w4-l10n-ime
→ w5-n3-firstboot → w5-n4-finished-meta → w5-d4-context-menu → w5-r4-install-hooks → w5-i3-target-identity → w5-b4-disable-upstream-init → w5-w4-wincompat-gui → w5-grt-session
→ w6-n5-install-e2e → w6-i4-installed-boot → w6-f5-target-flathub → w6-b5-meta-audit → w6-r5-deep-uninstall → w6-w6-wincompat-e2e → w6-hw1-live-usb → w6-doc1-user-docs
→ w7-re-manifest-gpg → w7-re-apt-repo → w7-ci-nightly → w7-perf-legal-gate
→ w8-hw-matrix → w8-s2-initrd-core → w8-s3-initrd-bottom → w8-s4-initramfs-hooks → w8-doc-handbook
→ w8-mvp-closeout
```

## 規則

1. 每 stage PASS → Hermes 自動 launch 下一段（**不詢問使用者**）
2. FAIL → inject Cursor 自修；連續 FAIL >10 → 通知使用者
3. 最終 `w8-mvp-closeout` PASS → `make test-wave-all-pass` 全綠 + MVP 報告

## 延後 5 項（不新增 stage）

v4 審計標記的 P2/P3 能力 **不阻擋** closeout，併入既有 stage。詳見 `strawwu-deferred-scope.md`：

| # | 能力 | Wave 觸點 | v0.5 |
|---|------|-----------|------|
| 1 | 多使用者 | w5-n3, w5-grt | 單使用者 |
| 2 | 備份/時光機 | w3-b3, UPG | rollback only |
| 3 | opt-in 統計 | w2-trust, w7-perf-legal | 預設關 |
| 4 | 社群渠道 | w6-doc1, w8-doc | 佔位 |
| 5 | shell 插件 | w4-d2 | v1.0 |

## 監看

```bash
python3 ~/.hermes/scripts/hermes_task_worker.py watch strawwu
make test-wave-all-pass   # 目前進度（預期 FAIL 直到全完成）
cat docs/plans/baselines/wave-status.json
```
