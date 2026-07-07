# StrawWU Logo 配色表

| 用途 | 色碼 | 說明 |
|---|---|---|
| 深色背景 | `#0A0E14` | 主背景，接近黑藍色 |
| Linux / 主結構 Teal | `#14B8A6` | 上方三角與左側 runtime |
| Windows / Bridge Amber | `#F59E0B` | 中間橋接橫線 |
| Straw 品牌金 | `#D4A853` | 下方穩固基底 |
| Bridge Blue | `#60A5FA` | 右側 bridge / runtime 輔助色 |
| 淺色文字 | `#F4F6F9` | StrawWU 主字標 |
| 副標灰藍 | `#A9B6C3` | `Desktop OS · Dual Runtime` |

## CSS 變數

```css
:root {
  --strawwu-bg: #0A0E14;
  --strawwu-teal: #14B8A6;
  --strawwu-amber: #F59E0B;
  --strawwu-straw-gold: #D4A853;
  --strawwu-bridge-blue: #60A5FA;
  --strawwu-text: #F4F6F9;
  --strawwu-muted: #A9B6C3;
}
```

## Tailwind 對應建議

| StrawWU 色彩 | Tailwind 近似 |
|---|---|
| `#0A0E14` | `slate-950` / 自訂色 |
| `#14B8A6` | `teal-500` |
| `#F59E0B` | `amber-500` |
| `#D4A853` | 自訂 straw-gold |
| `#60A5FA` | `blue-400` |
| `#F4F6F9` | `slate-50` |
| `#A9B6C3` | `slate-400` / 自訂 muted |

## 品牌語意

- `#14B8A6`：Linux / 系統層 / 穩定
- `#F59E0B`：Windows runtime / 調度橋接
- `#D4A853`：StrawCoding 品牌識別 / 基底
- `#60A5FA`：kernel bridge / userspace bridge
- `#0A0E14`：工程感深色桌面 OS 主題

## GPT 生成
- https://chatgpt.com/c/6a465d84-1ea8-83ee-9797-e831cde68894