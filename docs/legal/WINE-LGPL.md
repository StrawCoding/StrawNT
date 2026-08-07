# Wine／Proton-GE — LGPL 合規說明（StrawNT）

- **Product:** StrawNT
- **Date:** 2026-08-07
- **Stage:** NTW0（骨架；完整 notices 隨 NTW1 vendor 補齊）

## Honesty

StrawNT 旗艦執行層以 **Wine**（經 **Proton-GE** 上游樹）為基板。產品必須誠實標示：

> **powered by Wine** · `execution_backend=wine` · `engine=proton-ge@<pin>`

禁止將 Wine 靜默改名成「自研 PE」或「完整 Windows」。

## License posture

| 元件 | 預期授權 | 說明 |
|------|----------|------|
| StrawNT 殼（CLI／Hub／App Manager 等自有碼） | **MIT**（見根目錄 `LICENSE`） | 本倉庫自有部分 |
| Wine 及多數 Wine 衍生碼 | **LGPL-2.1**（部分檔案另有標註） | 隨 vendored 樹上 LICENSE 為準 |
| Proton-GE／相關補丁 | 上游各檔 LICENSE／COPYING | pin 後抄入 `THIRD_PARTY_NOTICES` |
| DXVK／vkd3d 等 | 上游（多為 zlib／MIT／LGPL 等） | pin 後列入 notices |

## Release requirements（每個發行）

1. 附上根目錄 **`THIRD_PARTY_NOTICES`**（或等價路徑）列出 Wine／GE／DXVK 等第三方。
2. 提供 **LGPL source offer**：書面／URL 說明如何取得對應版本的 Wine／GE 對應原始碼（含 StrawNT 對 LGPL 部分的修改，若有）。
3. UI／`strawnt status`／文件狀態列顯示 **powered by Wine**。
4. 不得在二進位發行中剝離使用者行使 LGPL 權利所需的對應資訊。

## Source offer（骨架）

在 Proton-GE 於 `third_party/proton-ge/` 以 **git-lfs** pin 後，source offer 預設指向：

- 本倉庫對應 tag／commit 的 `third_party/proton-ge/` 與 PIN 檔
- 上游 GE-Proton／Wine 官方原始碼 URL（寫入該次 release 的 `THIRD_PARTY_NOTICES`）

NTW0 **尚未** vendor 完整 GE 樹；本檔為合規契約骨架，NTW1 補齊 pin、checksum 與完整 notices 條目。

## Contact

StrawCoding — 透過本倉庫 GitHub Issues／Release notes 公布 source offer URL。
