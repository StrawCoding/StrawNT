# W0 Baseline 階段報告

| 任務 | W0-baseline |
|------|-------------|
| 版本 | 0.4.0.2 |
| 日期 | 2026-07-04 |
| 結果 | **PASS** |

## 交付物

| 類型 | 路徑 |
|------|------|
| 任務書 | `docs/plans/kickoff/W0-baseline.md` |
| 共用函式庫 | `tests/preflight/lib/common.sh` |
| 12 preflight | `tests/preflight/test-*.sh` |
| 基線 JSON | `docs/plans/baselines/{release,obs,perf}-baseline.json` |
| Makefile | `test-wave0-baseline` target |

## 測試

```bash
make test-wave0-baseline   # PASS
make preflight             # PASS
```

## W0 基線摘要

| 指標 | 值 |
|------|-----|
| squashfs ubuntu-* 套件 | 18 |
| squashfs strawwu-* deb | 0 |
| flatpak | 未安裝 |
| snapd | 已安裝（Wave F2 移除） |
| 最新 ISO | StrawWU-0.4.0.1-amd64.iso · 6.07 GB |
| squashfs | 5.08 GB |
| /usr/bin/strawwu in rootfs | 否（Wave W0 整合） |
| init deb 四件套 | 未建立（Wave N1） |

## 已知 WARN（預期）

- deb scaffold 全缺（N1/F1/R1）
- app-registry.schema.json 待 R0 凍結
- squashfs 無 strawwu CLI
- apport 套件名在 squashfs 掃描中未命中（子套件 apport-gtk 等存在）

## 下一步（Wave 1）

依序啟動（不並行同一 ISO）：

1. **W1-B1** — purge apport/whoopsie/ubuntu-pro/snapd
2. **W1-F1** — strawwu-flatpak-setup deb
3. **W1-F2** — 移除 snapd meta 依賴
4. **W1-S1** — initrd 低風險替換

Kickoff：`docs/plans/kickoff/W1-B1-purge.md`（待建）
