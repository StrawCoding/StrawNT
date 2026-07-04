# StrawWU PRD v0.5

| 版本 | 0.5 PRD |
|------|---------|
| 日期 | 2026-07-04 |
| 產品版本目標 | v0.5.0.0 (MVP) |

## 1. 產品一句話

StrawWU 是**可安裝的桌面 OS**，在 Linux 原生體驗之上提供**受控的 Windows 應用相容**，面向需要雙生態工作流的使用者。

## 2. 目標使用者

- 需要在 Linux 桌面跑部分 Windows 工具/遊戲的進階使用者
- 不想維護 Wine/Proton 碎片設定的人
- 接受「誠實 compat 分級」而非 100% Windows 替代

## 3. 使用場景

1. Live USB 試用 → 安裝 → firstboot → 日常瀏覽/辦公（Flathub）
2. 安裝 Windows 小工具 → 桌面啟動 → Hub 查看 compat 等級
3. 問題回報 → 本地 bundle → 可選上傳

## 4. 非目標（v0.5 不做）

- 完整 Windows 替代 / 全遊戲 catalog PASS
- Secure Boot 強制
- 企業 AD 整合
- 自研 compositor（D5）
- per-app 預設 sandbox（container 僅可選）

## 5. MVP 必備（v0.5.0.0）

- 全程 StrawWU 品牌（開機→桌面→安裝→firstboot）
- Flathub 預設、無 Snap
- strawwu-bug-reporter + Hub
- strawwu-calamares-settings + firstboot
- strawwu-shell/session 最小可用
- App Registry list/remove
- Windows compat：至少 1 GUI app E2E smoke
- release-iso + SHA256 + boot/install E2E

## 6. v1.0 才做

- Secure Boot 簽章鏈
- 完整 HW 矩陣 stable gate
- Office/Steam/Epic launcher（Phase 8）
- self-hosted CI（Q6）

## 7. 競品差異

| 對手 | StrawWU 差異 |
|------|--------------|
| Ubuntu | 自訂 kernel + Windows compat + 無 Snap |
| Mint | 更深度 initrd + compat stack |
| Zorin | 自研 Hub + Registry 統一 app |
| Pop!_OS | Windows 路徑非 Wine 為主 |

## 8. 成功指標

| 指標 | v0.5 目標 |
|------|-----------|
| 安裝成功率（QEMU E2E） | 100% |
| firstboot 完成率 | ≥95% 新裝 |
| bug bundle 生成成功率 | 100% CLI |
| 日常 Flathub app 可用 | ≥3 app smoke PASS |
| Windows GUI smoke | ≥1 app PASS |
