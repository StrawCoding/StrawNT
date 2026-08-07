# NTW8 — Golden Closeout 階段報告

| 任務 | ntw8-golden-closeout |
|------|----------------------|
| Track | StrawNT Wine pivot |
| 產品 | StrawNT |
| 版本 | 見 `VERSION`（本 stage bump） |
| 日期 | 2026-08-08 |
| Worker | 階段 9/9 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS；須 trigger-verify + OpenCode APPROVE） |

## 目標

line.exe＋steam.exe 嚴格矩陣（install／launch／可見 UI／PARTIAL 註記／engine pin／證據路徑）；真實視窗觀測；HTML／JSON closeout；`tests/strawnt/output/ntw8-golden.json` 頂層 PASS。禁 simulated；禁排位宣稱。bump＋push＋必要 Release。

## 交付物

| 類型 | 路徑 |
|------|------|
| 黃金腳本 | `tests/strawnt/ntw8-golden.sh` |
| 證據 JSON | `tests/strawnt/output/ntw8-golden.json` |
| 證據 HTML | `tests/strawnt/output/ntw8-golden.html` |
| 視窗截圖 | `tests/strawnt/output/ntw8/shots/{line,steam,steam-setup}.png` |
| 樹／match | `tests/strawnt/output/ntw8/shots/*.{tree,match,found}` |
| Launch mode | `tests/strawnt/output/ntw8/steam-launch-mode.txt`（= `steam_exe`） |

## 前序階段

| Stage | 狀態 |
|-------|------|
| ntw0-contract-legal | PASS |
| ntw1-vendor-engine | PASS |
| ntw2-shell-electron | PASS |
| ntw3-optimize | PASS |
| ntw4-win32-ipc | PASS |
| ntw5-app-manager | PASS |
| ntw6-sysapps | PASS |
| ntw7-packaging | PASS |

## 嚴格矩陣（誠實）

| App | 頂層 | install | launch | visible_ui | login | 備註 |
|-----|------|---------|--------|------------|-------|------|
| line.exe | PARTIAL | PASS | PASS | PASS | UNKNOWN | NSIS＋crypt32 shim；Banner/LineLauncher 真實視窗 |
| steam.exe | PARTIAL | PASS | PASS | PASS | UNKNOWN | `launch_mode=steam_exe`；Steam.exe「Updating Steam…」真實視窗；SteamSetup 僅 install-UI |

引擎：`execution_backend=wine` · `proton-ge@GE-Proton11-3` · **powered by Wine**

## OpenCode tick-16 gaps（已閉環）

1. **SteamSetup ≠ steam.exe launch**：harness 強制 `launch_mode=steam_exe`；installer 標題（`Steam 安裝`／Setup／安裝精靈）硬拒絕作為 launch 證據；`steam.png` 與 `steam-setup.png` 分離且 sha256 不同。
2. **HTML／JSON provenance 原子一致**：同一 provenance block 寫入 JSON 頂層＋`provenance`＋HTML meta／pills。

## 本地閘門（worker 自測；最終 mark 仍待 Hermes）

```bash
test -f tests/strawnt/output/ntw8-golden.json
jq -e '.status == "PASS"' tests/strawnt/output/ntw8-golden.json
jq -e '.mode != "simulated"' tests/strawnt/output/ntw8-golden.json
jq -e '(.apps.line.status != null) or (.matrix.line.status != null) or (.claims.line == true)' tests/strawnt/output/ntw8-golden.json
jq -e '(.apps.steam.status != null) or (.matrix.steam.status != null) or (.claims.steam == true)' tests/strawnt/output/ntw8-golden.json
jq -e '(.claims.ranked_pass_claimed // false) == false' tests/strawnt/output/ntw8-golden.json
jq -e '.apps.steam.launch_mode == "steam_exe"' tests/strawnt/output/ntw8-golden.json
jq -e '.checks.steam_exe_launch.status == "PASS"' tests/strawnt/output/ntw8-golden.json
```

## 誠實邊界（已遵守）

- App 列維持 **PARTIAL**（login／all_games UNKNOWN）
- `ranked_pass_claimed=false`；無官方反作弊／排位宣稱
- `mode=real`（Xvfb＋xwininfo＋PNG）；非 simulated
- Hub 維持 Electron；旗艦引擎 GE-vendored
- 未宣稱完整 Windows／所有遊戲可玩

## 建議狀態

**建議 Hermes：PASS**（證據齊備；待 OpenCode acceptance APPROVE 後 mark）

## 未完成／閘門外

- OpenCode acceptance 重審（tick-16 REQUEST_CHANGES 之後的重驗）由 Hermes 觸發
- login／全功能／all_games 仍 UNKNOWN（刻意不宣稱）
