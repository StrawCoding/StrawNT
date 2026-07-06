# StrawWU HW4 筆電周邊策展計畫

| 版本 | 1.0 |
|------|-----|
| 對照維度 | E10 觸控板/Fn、E15 webcam/指紋 |
| Stage | `post-hw4-peripherals` |

## 目標

對標 Mint mint-meta / Pop system76-power 基礎策展：

1. `strawwu-laptop-meta` 或等效 meta：tlp、觸控板驅動、Fn 鍵基線
2. fprintd + 指紋登入 smoke（有硬體時）
3. webcam PipeWire smoke（有硬體時）
4. `hw-matrix-results.json` 新增 T2 peripheral 條目（非 SKIP）

## 驗收

`make test-hw4-peripherals` + stage report
