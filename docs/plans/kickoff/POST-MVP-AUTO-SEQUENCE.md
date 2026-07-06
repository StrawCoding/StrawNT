# StrawWU Post-MVP 全自動鎖序

| 項目 | 值 |
|------|-----|
| 總 stage 數 | **12** |
| 起點 | `post-d1-strawwu-drivers`（MVP closeout 後自動啟動） |
| 終點 | `post-v09-engineering-closeout` |
| 接續腳本 | `longtask_post_mvp_transition_next.sh` |
| 路由 | `longtask_transition_dispatch.sh` |
| 路線圖 | `docs/plans/strawwu-post-mvp-roadmap.md` |

## 鎖序

```
post-d1-strawwu-drivers
→ post-hw-t1-live-usb
→ post-hw-t2-installed
→ post-ddp-rootfs
→ post-q3-mfp-smoke
→ post-v06-closeout
→ post-upg-rollback
→ post-sec-secureboot-route
→ post-ci-kernel-selfhosted
→ post-hw-t3-wincompat
→ post-q8-golden-apps
→ post-v09-engineering-closeout
```

## 規則

1. `w8-mvp-closeout` PASS 後 Hermes **自動** launch `post-d1-strawwu-drivers`
2. 每 post stage PASS → 自動 launch 下一段（**不詢問使用者**）
3. v1.0 正式版不在此鎖序 — 需使用者授權

## 監看

```bash
python3 ~/.hermes/scripts/hermes_task_worker.py watch strawwu
make test-post-mvp-all-pass
cat docs/plans/baselines/post-mvp-status.json
```
