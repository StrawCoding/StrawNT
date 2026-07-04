# Bridge ABI 規格

| 版本 | 0.3.0-cleanroom |
|------|-----------------|
| 日期 | 2026-07-04 |
| 對齊 | `runtime-cooperation.md`、`execution-backends.md`、Phase 2 `strawwu_ipc` |

## 目標

定義 `strawwu-bridge` 在 kernel↔userspace 之間的 IPC 協定，作為 Win32 子系統與 Linux kernel 之間的翻譯層。Bridge 不是第二個 OS，而是 seccomp/policy 控制的系統呼叫橋接。

## ABI 訊息格式（BridgeRequest）

所有 bridge 通訊使用固定大小 header + 可變長度 payload：

```
┌──────────────────────────────────────────┐
│ BridgeHeader (32 bytes)                  │
├──────────────────────────────────────────┤
│ magic: u32        = 0x53574232 ("SWB2")  │
│ version: u16      = 1                    │
│ msg_type: u16     (Request/Response/Event)│
│ seq_id: u64       (monotonic)            │
│ payload_len: u32                         │
│ flags: u32                               │
│ reserved: u64                            │
└──────────────────────────────────────────┘
│ Payload (variable, max 64KB)             │
└──────────────────────────────────────────┘
```

### msg_type 枚舉

| 值 | 名稱 | 方向 | 說明 |
|----|------|------|------|
| 0x01 | SyscallRequest | app→bridge | Win32 syscall 翻譯請求 |
| 0x02 | SyscallResponse | bridge→app | 翻譯結果 |
| 0x03 | PolicyQuery | bridge→runtime | 政策查詢 |
| 0x04 | PolicyDecision | runtime→bridge | 允許/拒絕/審計 |
| 0x10 | SessionEvent | runtime→bridge | session 生命週期事件 |
| 0x11 | ProcessEvent | bridge→runtime | 行程建立/終止 |

## 傳輸層

| 後端 | 傳輸 | 適用 |
|------|------|------|
| native | Unix domain socket (SOCK_SEQPACKET) | 預設 |
| container | 同上（namespace 內） | 隔離覆寫 |
| microvm | vsock (AF_VSOCK) | VM 內 |

Socket 路徑：`/run/strawwu/bridge-{session_id}.sock`

## Seccomp Policy

Bridge 在 app 行程啟動時注入 seccomp-bpf filter：

- `syscall_profile: daily` — 允許常用 syscall；阻擋 `ptrace`、`process_vm_*`
- `syscall_profile: game` — 額外允許 perf/timer 相關
- `syscall_profile: anticheat` — 嚴格 allow-list + IOCTL 回應表

Policy 由 runtime 下發，bridge 執行。

## 生命週期

```
1. runtime 建立 SubsystemSession
2. runtime 啟動 bridge daemon（strawwu-bridged）
3. launcher 啟動 PE/ELF → 連接 bridge socket
4. app 發出 BridgeRequest（syscall / IPC / device）
5. bridge 翻譯 → Linux syscall 或轉發至 runtime
6. app 結束 → bridge 通知 runtime（ProcessEvent）
7. session 空閒 → bridge daemon 可休眠
```

## 錯誤碼

| 碼 | 名稱 | 說明 |
|----|------|------|
| 0 | OK | 成功 |
| 1 | EPERM | 政策拒絕 |
| 2 | ENOSYS | 未實作的 syscall |
| 3 | EINVAL | 無效參數 |
| 4 | ESESSION | session 不存在或已終止 |
| 5 | EBRIDGE | bridge 內部錯誤 |

## 驗收

```bash
make -C components test    # bridge ABI 序列化/反序列化 round-trip
```
