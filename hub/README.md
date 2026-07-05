# StrawWU Hub / Settings Center

Electron-based system settings center for StrawWU (W4-D3).

## Panels

- Subsystem status, logs, update channel, language
- Windows compatibility (session status + compat grades)
- System shortcuts (GNOME control panels)
- About (legal docs, bug reporter)

## Development

```bash
npm install
npm start
npm test
```

## Verification

```bash
make -C components test-hub
make test-hub-settings
```

Also reachable via symlink: `components/strawwu-hub` → `hub/`.
