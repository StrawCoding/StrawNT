# StrawWU 延後範圍（v4 完整性審計）

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |
| 關聯 | Master Plan v4 · Wave 0→8 自動鎖序（47 段） |

## 用途

v4 完整性審計標記 **5 項未獨立立項** 的能力。本文件定義：

1. 併入哪個子計畫 / Wave stage
2. v0.5 MVP **必做 vs 可延後** 邊界
3. 是否為 `w8-mvp-closeout` 的 blocking DoD

**原則：** 這 5 項 **不新增 Wave stage**；47 段自動管線照常跑完即 MVP PASS。

---

## 總表

| # | 能力 | 併入計畫 | 觸及 Wave stage | 優先 | v0.5 MVP | v1.0+ |
|---|------|----------|-----------------|------|----------|-------|
| 1 | 多使用者 / 家庭帳號 | N3 firstboot + GRT | w5-n3, w5-grt-session | P2 | 單使用者即可 | 家庭帳號精靈 |
| 2 | 備份 / 時光機 | UPG snapshot | w6（upgrade hook 預留） | P2 | snapshot 預留介面 | strawwu-backup PoC |
| 3 | opt-in 使用統計 | SEC + LEG privacy | w2-trust, w7-perf-legal | P3 | **預設關閉** | 完整 opt-in 管線 |
| 4 | 社群 / 支援渠道 | DOC + PRD | w6-doc1, w8-doc-handbook | P3 | 佔位連結即可 | 論壇 / Matrix |
| 5 | shell 插件 API | D2 strawwu-shell | w4-d2 | P3 | fork + 內建 Dock | extension point |

---

## 1. 多使用者 / 家庭帳號（P2）

**併入：** `strawwu-install-init-plan.md` · `strawwu-greeter-session-plan.md`

**Wave stage：**
- `w5-n3-firstboot` — 僅建立 **primary 使用者**；不實作子帳號 / 家長控制
- `w5-grt-session` — GDM 單使用者登入；不實作 fast user switching UI

**v0.5 DoD（blocking）：**
- firstboot 完成後僅一個桌面使用者
- `state.json` 無 multi-user schema 要求

**v0.5 不做（deferred）：**
- 家庭帳號精靈、子帳號限時、家長控制
- Hub「使用者與家庭」分頁

**v1.0 路線：** Hub 新增 Users 分頁 + polkit 權限模型

---

## 2. 備份 / 時光機（P2）

**併入：** `strawwu-upgrade-recovery-plan.md`

**Wave stage：**
- `w3-b3-update-notifier` — 升級前 **提示備份**（文案 only）
- `w6-*` — UPG rollback 預留 snapshot hook（見 upgrade-recovery §3）
- **不** 新增 `w*-backup` stage

**v0.5 DoD（blocking）：**
- `strawwu-upgrade` 升級失敗可 rollback kernel/initrd（UPG 計畫範圍）
- 無 Timeshift 替代品要求

**v0.5 不做（deferred）：**
- `strawwu-backup` GUI / 排程 / Btrfs 時光機
- 使用者文件中的「備份教學」可為佔位

**v1.0 路線：** `strawwu-backup` PoC（rsync + manifest + Hub 還原）

---

## 3. opt-in 使用統計（P3）

**併入：** `strawwu-security-trust-model.md` · `strawwu-legal-compliance-plan.md`

**Wave stage：**
- `w1-b1-purge` — 移除 ubuntu-report / whoopsie（**必做**）
- `w2-trust-baseline` — privacy 預設關閉、bug consent 流程
- `w7-perf-legal-gate` — privacy policy / EULA 草案含「無預設遙測」條款

**v0.5 DoD（blocking）：**
- 零預設上傳 Canonical / 第三方 analytics
- firstboot 隱私步驟明確 opt-in（bug 回報以外預設關）

**v0.5 不做（deferred）：**
- 匿名使用統計收集器、telemetry daemon
- Hub「隱私與資料」中的統計開關後端

**v1.0 路線：** opt-in `strawwu-stats` + 本地聚合 + 使用者可匯出/刪除

---

## 4. 社群 / 支援渠道（P3）

**併入：** `strawwu-user-docs-plan.md` · `strawwu-prd-v0.5.md`

**Wave stage：**
- `w6-doc1-user-docs` — About / Help 佔位連結（可 `TBD`）
- `w8-doc-handbook` — 支援渠道章節 stub

**v0.5 DoD（blocking）：**
- **非工程 blocking** — 不阻擋 `w8-mvp-closeout`
- Hub「關於」顯示版本 + bug-reporter 入口即可

**v0.5 不做（deferred）：**
- 論壇、Matrix room、Discord、工單系統整合

**v1.0 路線：** 官方支援 URL + 社群規範文件

---

## 5. strawwu-shell 插件 API（P3）

**併入：** `strawwu-desktop-plan.md`

**Wave stage：**
- `w4-d2-strawwu-shell` — fork GNOME Shell、內建 Dock、移除 Ubuntu 擴充

**v0.5 DoD（blocking）：**
- 穩定 panel / overview / 通知
- **不要求** 第三方 extension 載入

**v0.5 不做（deferred）：**
- `StrawWU.Extension` D-Bus API
- 插件市集、簽章插件

**v1.0 路線：** extension point 規格 + 沙箱載入（見 desktop-plan D5）

---

## 與 w8-mvp-closeout 的關係

`make test-wave-all-pass` 與 `w8-mvp-closeout` **不要求** 上表 5 項完整實作。

| 項目 | 影響 closeout |
|------|---------------|
| 1 多使用者 | ❌ 不 blocking |
| 2 備份 | ❌ 不 blocking（UPG rollback 另計） |
| 3 遙測 | ✅ 部分 blocking（purge + 預設關） |
| 4 社群 | ❌ 不 blocking |
| 5 插件 API | ❌ 不 blocking |

---

## Cursor / Hermes worker 規則

1. 執行 w5-n3 / w5-grt / w4-d2 等 stage 時 **勿擴 scope** 至延後項
2. stage report 若觸及延後項，標記 `DEFERRED-P2` 或 `DEFERRED-P3`
3. 連續 FAIL 不得用「順便做備份/插件」當藉口改 kernel 或 ISO 管線

---

## 變更紀錄

| 日期 | 變更 |
|------|------|
| 2026-07-04 | v1.0 初版 — 對齊 v4 審計 5 項 |
