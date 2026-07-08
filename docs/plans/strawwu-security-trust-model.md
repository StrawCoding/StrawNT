# StrawWU Security / 信任鏈計畫

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |

## 1. 威脅模型摘要

StrawWU 同時是 Linux 發行版 + Windows compat 宿主。信任邊界：

1. Boot chain（firmware → kernel → initrd → rootfs）
2. Package trust（APT / Flatpak / 自製 deb）
3. User data（bug bundle、Registry、Windows VFS）
4. Privilege（root vs user vs SubsystemSession）

## 2. Secure Boot

| 階段 | 策略 |
|------|------|
| v0.4–0.5 | **不強制 SB**；文件誠實標「未簽 SB shim」 |
| v0.6–0.7 | **路線文件 + 骨架**（`post-sec-secureboot-route`）；預設仍不強制啟用 |
| v0.8+ | 自建或第三方 shim + **signed kernel** + **signed initrd** 可選啟用 |
| 金鑰 | 獨立 StrawWU UEFI DB；不混用 Ubuntu shim（商標+信任） |

### 2.1 Boot chain（目標）

```
UEFI firmware (DB/DBX)
    → shim.efi（StrawWU 或第三方簽章，PE/COFF）
    → grubx64.efi（由 shim 驗證）
    → signed kernel（vmlinuz，sbsign / pesign）
    → signed initrd（initrd.img，可選 UKI 合併）
    → rootfs（dm-verity 留待 v1.0）
```

### 2.2 v0.7 骨架（不強制）

| 元件 | 路徑 | 說明 |
|------|------|------|
| CLI | `strawwu-secureboot` | `status` / `route` / `preflight`；fixture 模式可離線測 |
| 簽章腳本 | `os-image/scripts/secureboot-route/sign-boot-artifacts.sh` | 預設 `--dry-run`；`STRAWWU_SB_SIGN=1` + 金鑰才實簽 |
| 驗證腳本 | `os-image/scripts/secureboot-route/verify-boot-chain.sh` | `mokutil` / `sbverify` 可用性 + 產物 hash |
| 清單 | `usr/share/strawwu/secureboot/secureboot-manifest.yaml` | 路線、金鑰槽、啟用旗標 |
| Hub 警告 | `strawwu-drivers` | SB 啟用時誠實標未簽模組；連結本計畫 |

**預設旗標**：`STRAWWU_SECURE_BOOT_ENFORCE=0`（安裝與 ISO 不強制 SB）。Calamares 仍可選裝 `shim-signed` 作過渡，但 StrawWU 正式路線使用獨立 DB。

### 2.3 金鑰與簽章（規劃）

| 金鑰 | 用途 | 儲存 |
|------|------|------|
| StrawWU-SB-DB | shim + grub + kernel PE 簽章 | CI secret / 離線 HSM（v0.8+） |
| StrawWU-MOK | 第三方 DKMS 模組 MOK 註冊 | 使用者本機 `mokutil` |
| StrawWU-APT | deb/ISO GPG（見 SEC1/RE2） | `strawwu-keyring` |

Kernel 目標：`CONFIG_MODULE_SIG=y`、`CONFIG_MODULE_SIG_FORCE` 預設 **關**（與 Hub 驅動警告一致）；啟用 SB 時改由發行版 policy 文件化。

## 3. Kernel / Module Signing

- `linux-image-strawwu`：目標 CONFIG_MODULE_SIG=y
- 自訂模組 `strawwu_ipc`：隨 kernel 簽章或 MOK 註冊流程（文件化）
- DKMS 第三方驅動：Hub 顯示「未簽模組」警告

## 4. ISO / deb / APT 簽章

| 產物 | 機制 |
|------|------|
| ISO | SHA256SUMS + detached GPG |
| deb pool | `reprepro` + Release.gpg |
| Flatpak | flathub 上游 OSTree 簽章（不二次簽） |
| initrd splice | build 後 hash 寫入 manifest |

## 5. CVE Patch Policy

| 階段 | 策略 |
|------|------|
| v0.5 | 僅文件化 SLA；依 Ubuntu noble security 上游 |
| v0.6–0.7 | **USN 追蹤骨架 + CI 通知骨架**（`post-sec-cve-policy`）；不自動套用 patch |
| v0.8+ | CI 自動開 issue / 通知維護者；kernel 與 strawwu-* deb 獨立 CVE 閘門 |
| 正式版 | 與 release channel 綁定；security advisory 隨 manifest 發布 |

### 5.1 USN 追蹤（Ubuntu noble）

StrawWU 基於 Ubuntu noble（24.04 LTS）rootfs，**預設繼承 noble-security / noble-updates**：

| 來源 | 追蹤方式 | StrawWU 動作 |
|------|----------|--------------|
| USN（Ubuntu Security Notice） | `track-usn.sh` 每日/每週掃描 | 記錄受影響套件；比對 squashfs manifest |
| CVE（NVD / Ubuntu CVE tracker） | 交叉引用 USN 編號 | critical/high 進入 72h 評估佇列 |
| noble-hwe kernel | `linux-image-strawwu` 對照 HWE 標籤 | 自有 kernel 分支 cherry-pick 或 rebase |
| strawwu-* 自製 deb | `components/` + `os-image/debs/` 清單 | 72h 內評估；critical 7d 內 patch tag |
| Windows compat（Rust） | `cargo audit`（CI 骨架） | 不載入 Windows .sys；獨立修補 wincompat crate |

**追蹤腳本**（預設 fixture/dry-run，不對外連線）：

```
os-image/scripts/cve-policy/track-usn.sh      # USN/CVE 掃描骨架
os-image/scripts/cve-policy/notify-cve-policy.sh  # 通知 payload 骨架
```

環境變數：`STRAWWU_CVE_FIXTURE=1`（離線測試）、`STRAWWU_CVE_NOTIFY=0`（預設不發送）。

### 5.2 SLA 與嚴重度

| 嚴重度 | 定義 | StrawWU 自訂套件 | 上游 noble 套件 |
|--------|------|------------------|-----------------|
| critical | 遠端未授權 RCE / 權限提升 | 7 日內 patch tag | 隨 USN 建議 ASAP |
| high | 本地提權 / 重要資料外洩 | 14 日內評估 | 下一個 point release |
| medium | 需使用者互動的漏洞 | 下一個 minor | 隨 noble-updates |
| low / negligible | 資訊揭露、DoS（非預設路徑） | backlog | 隨上游 |

**kernel**：`linux-image-strawwu` 跟 noble-hwe 或自有 strawwu kernel 分支；critical CVE 優先 cherry-pick。

**Windows compat**：不載入 Windows `.sys`；Rust 層 CVE 由 `cargo audit` 獨立追蹤（見 §5.3）。

### 5.3 v0.7 骨架（不自動修補）

| 元件 | 路徑 | 說明 |
|------|------|------|
| CLI | `strawwu-security` | `status` / `track` / `notify` / `preflight`；fixture 模式可離線測 |
| 追蹤腳本 | `os-image/scripts/cve-policy/track-usn.sh` | 預設 `--dry-run`；`STRAWWU_CVE_FIXTURE=1` 讀 fixture |
| 通知腳本 | `os-image/scripts/cve-policy/notify-cve-policy.sh` | 預設 `--dry-run`；輸出 JSON payload，不發 webhook |
| 清單 | `usr/share/strawwu/security/security-manifest.yaml` | SLA、來源、啟用旗標 |
| CI | `.github/workflows/security-advisory.yml` | 每週掃描 + `make test-sec-cve-policy` 閘門 |

**預設旗標**：`STRAWWU_CVE_NOTIFY=0`（不自動發送通知）。Webhook / issue 建立留待 v0.8+ CI secret 佈署。

### 5.4 SEC6 交付對照（v0.7.0）

| 檢查 | 命令 / 路徑 |
|------|-------------|
| 政策文件 | 本節 §5 + `docs/plans/kickoff/POST-SEC-cve-policy.md` |
| 靜態閘門 | `make test-sec-cve-policy` |
| Baseline | `docs/plans/baselines/cve-policy-baseline.json` |
| Stage report | `docs/plans/stage-reports/POST-SEC-cve-policy-report.md` |
| CI 通知骨架 | `.github/workflows/security-advisory.yml` |

## 6. 權限邊界

| 元件 | 執行身份 | 限制 |
|------|----------|------|
| strawwu-bug-reporter | user | 僅讀允許 log；不上傳除非同意 |
| strawwu-app-registry remove | user + polkit | protected app 拒絕 |
| deep uninstall | admin prompt | 禁止刪 `/usr`、`/etc` 系統路徑 |
| Windows SubsystemSession | 容器 user namespace（native 預設） | 不直通 host kernel |
| strawwu-target-setup | root chroot | Calamares 限定 |

## 7. Bug Report 隱私

- **預設**：本地 bundle only（`.strawwu-bug`）
- **上傳**：需 firstboot / Hub 明確 opt-in
- **收集**：VERSION、uname、journal 24h、dmesg、lsblk、非 secret 的 registry 摘要
- **排除**：/home 檔名、Wi-Fi PSK、SSH key、Windows 登入 token
- **保存**：上傳端 90 天；本地使用者自刪

## 8. App Registry / deep uninstall 安全

- `protected: true` 系統 app 不可 UI 移除
- remove 前 dry-run + 路徑 allowlist
- Windows app：僅刪 prefix + registry overlay；不碰 host `/`

## 9. Windows Compat 隔離

- 預設 native shared session：同 session 互通；跨 session 隔離
- `--backend container`：bubblewrap/firejail 可選
- VFIO：僅 Tier4 PoC；預設關閉
- 不載入 Windows 驅動進 Linux kernel

## 10. Phase SEC0–SEC5

| Phase | 工作 |
|-------|------|
| SEC0 | 威脅模型文件 + 資產清單 |
| SEC1 | GPG keyring + ISO/deb 簽章（合 RE2） |
| SEC2 | bug-reporter 隱私過濾 + consent UI |
| SEC3 | Registry protected list + polkit |
| SEC4 | compat session 權限審計 |
| SEC5 | Secure Boot 路線圖 PoC（可選）— `strawwu-secureboot` + `secureboot-route/` 骨架；**signed kernel** + **signed initrd** 腳本 dry-run |
| SEC6 | CVE/USN 修補政策自動化（骨架）— `strawwu-security` + `cve-policy/` 追蹤/通知；CI `security-advisory.yml` |

## 11. SEC5 交付對照（v0.7.0）

| 檢查 | 命令 / 路徑 |
|------|-------------|
| 路線文件 | 本節 §2 + `docs/plans/kickoff/POST-SEC-secureboot-route.md` |
| 靜態閘門 | `make test-secureboot-route` |
| Baseline | `docs/plans/baselines/secureboot-route-baseline.json` |
| Stage report | `docs/plans/stage-reports/POST-SEC-secureboot-route-report.md` |
