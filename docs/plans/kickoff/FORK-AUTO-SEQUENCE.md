# StrawWU Fork 全自動鎖序

| 項目 | 值 |
|------|-----|
| 總 stage 數 | **7** |
| 前置 | Ubuntu 26.04 遷移 `u26-m7-closeout` PASS |
| 起點 | `fork-f1-baseline-snapshot` |
| 終點 | `fork-f7-closeout` |
| 路線圖 | `docs/plans/strawwu-fork-migration-plan.md` |

## 完整管線

```
Wave 47 → u26 7 段 → Fork 7 段（本文件）→ Post-MVP 21 段
```

## 鎖序

```
fork-f1-baseline-snapshot
→ fork-f2-manifest-repo
→ fork-f3-build-pipeline
→ fork-f4-package-overlays
→ fork-f5-apt-fork-suite
→ fork-f6-regression-e2e
→ fork-f7-closeout
```

## 規則

1. `u26-m7-closeout` PASS → 自動 launch `fork-f1-baseline-snapshot`（非直接 post-d1）
2. `fork-f7-closeout` PASS → 自動 launch `post-d1-strawwu-drivers`
3. fork-f7 後 `ubuntu-base-target.json` → `base_mode=fork`
