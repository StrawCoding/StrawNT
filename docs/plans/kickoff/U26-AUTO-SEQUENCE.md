# Ubuntu 26.04 Migration — Auto Sequence

| Track | Ubuntu 26.04 LTS (Resolute) |
|-------|----------------------------|
| 觸發 | `w8-mvp-closeout` PASS |
| 終點 | `u26-m7-closeout` → 自動接 `post-d1-strawwu-drivers` |
| 計畫 | `strawwu-ubuntu-2604-migration-plan.md` |

## 鎖序

1. u26-m1-base-clone
2. u26-m2-kernel-rebase
3. u26-m3-debs-rebuild
4. u26-m4-suite-migrate
5. u26-m5-techrefs-refresh
6. u26-m6-regression-e2e
7. u26-m7-closeout

## Hermes

每 stage PASS → 自動 launch 下一段，勿問使用者。
