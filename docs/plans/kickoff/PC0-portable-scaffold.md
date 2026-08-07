# Kickoff — pc0-portable-scaffold

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本 kickoff 為 native-era 任務書。其中「禁 Wine／Proton／Do not … Wine」為**歷史硬契約**，已廢止。現行產品預設 wine／proton-ge（powered by Wine）。見 `docs/plans/kickoff/README.md`、`docs/decisions/2026-08-07-wine-pivot.md`。

## 目標

建立 StrawWU **Portable Core A+3** 骨架：跨發行版可攜 Win 相容核心（runtime／nt／launcher／graphics·audio／Hub／CLI），優先自含 prefix + AppImage，Flatpak 次之。

## 專案路徑

`/mnt/data/code/project/StrawCoding/StrawWU-portable`  
分支：`portable-core-a3`

## 範圍

- 盤點可打包二進位與共享庫依賴  
- 新增 `components/packaging/portable/` 骨架（prefix / AppImage / Flatpak 目錄與 README）  
- 產出 `docs/plans/portable-core/inventory.json`（crate→artifact 對照）  
- 煙測入口 stub：`tests/portable/smoke-prefix.sh`（本 stage 可先檢查腳本存在與 `--help`／dry 結構）  
- 有原始碼／config 改動必 `bash scripts/bump-version.sh`  
- commit + push 本分支（本 stage 不 merge main；merge 留給 pc5）

## 禁止

- 改 ISO／os-image／Plymouth／Calamares／kernel／桌面 shell session  
- Wine／Proton 當底層  
- WinBox／winbox 命名、per-app sandbox 預設  
- 宣稱完整 Windows 相容  
- 動 `/mnt/data/code/project/StrawCoding/StrawWU` 主工作區（ISO T1 軌道）  
- `npm run gpr`／假 PASS

## PASS 條件

1. `docs/plans/portable-core/A3-cross-distro-core.md` 存在  
2. `docs/plans/portable-core/inventory.json` 存在且含 runtime／nt／launcher／cli／graphics／audio／hub 條目  
3. `components/packaging/portable/README.md` 存在  
4. `tests/portable/smoke-prefix.sh` 可執行  
5. `git status` 乾淨（改動已 commit）；分支已 push（若遠端可用）  
6. 版本已 bump（若有程式／配方改動）

## 驗證（僅 Hermes `trigger-verify` 執行）

Worker 完成後等 Hermes verify；勿自行宣稱 PASS。
