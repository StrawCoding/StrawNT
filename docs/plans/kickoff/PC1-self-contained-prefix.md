# Kickoff — pc1-self-contained-prefix

## 目標

產出不依賴系統 `strawwu-*` deb 的自含 `$STRAWWU_PREFIX`
（runtime／nt／launcher／cli／graphics／audio；Hub 可選同捆）。

## 專案路徑

`/mnt/data/code/project/StrawCoding/StrawWU-portable`  
分支：`portable-core-a3`

## 範圍

- `components/packaging/portable/build-prefix.sh` + `make portable-prefix`
- prefix 內 `bin/strawwu`（rpath → `lib/`）、本地 app-registry、manifest
- `tests/portable/smoke-prefix.sh` 寫入 `tests/portable/output/smoke-prefix.json`
- bump + commit + push（本 stage 不 merge main）

## 禁止

- 改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- Wine／Proton 當底層、WinBox 命名、宣稱完整 Windows 相容
- 動主工作區 `/mnt/data/code/project/StrawCoding/StrawWU`

## PASS 條件

1. `make portable-prefix`（或等價）產出可執行 prefix  
2. `$STRAWWU_PREFIX/bin/strawwu --version` 與 `status` 成功  
3. `tests/portable/output/smoke-prefix.json` 頂層 `status=PASS`  
4. 不依賴系統 `strawwu-*` deb  
5. 版本已 bump；工作區乾淨已 push

## 驗證（僅 Hermes `trigger-verify`）

Worker 完成後等 Hermes verify；勿自行宣稱最終 PASS。
