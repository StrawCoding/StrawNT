# NT6-openable-app report

## Summary
Version **0.7.1.39**. Fixed “i cant open app” root causes: stale StrawWU/`/tmp` MIME handlers blocked double-click; app-menu entry ran `open %f` with no file and failed; PATH after install was easy to miss.

## Fixes
1. `strawnt integrate` clears `strawwu-open.desktop`, broken TryExec `/tmp/...`, legacy MIME xml; rewrites mimeapps defaults to `strawnt-open.desktop`
2. App-menu `strawnt.desktop` → `status` (TryExec absolute); MIME handler `strawnt-open.desktop` is `NoDisplay=true`
3. `install.sh` ensures `~/.local/bin` PATH + `~/.config/strawnt/env.sh`; pre-clears stale handlers; supports `--local` for clean-env proof

## Evidence
- `tests/strawnt/output/nt6-openable.json` — status=PASS, mode=real
- Hermes subset: cli_available / desktop_exec_exists / stale_handler_cleared / open_log non-empty

## Exclusions honored
No Wine/Proton substrate; no ISO/StrawWU OS changes; no WinBox; no full Windows / ranked AC claim; no simulated top-level PASS.
