# POST-I2-calamares-luks

| 任務 ID | post-i2-calamares-luks |
|---------|-------|
| 計畫 | `strawwu-installer-advanced-plan.md` |
| 對照 | 對比書 C7、C8 |

## 目標

LUKS 加密安裝 + 雙系統偵測獨立驗證

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-calamares-luks-dualboot
make preflight
```

## 必須交付

1. calamares/install-e2e 產物
2. `docs/plans/stage-reports/POST-I2-calamares-luks-report.md`
3. VERSION bump

## 完成後

Hermes mark PASS → 自動啟動 `post-d7-software-sources`
