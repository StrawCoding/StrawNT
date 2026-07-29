# AppImage bundle (pc2)

Build a Type-2 **AppImage** (when `appimagetool` can be fetched) plus an
equivalent single-directory **AppDir** and `.portable.tar.gz` from the
self-contained prefix.

```bash
make portable-prefix          # if needed
make portable-appimage
make test-portable-appimage   # clean-container smoke → smoke-appimage.json + SHA256SUMS
```

Artifacts land in `components/packaging/portable/appimage/dist/` (gitignored):

| File | Role |
|------|------|
| `StrawNT-<ver>-x86_64.AppDir/` | Runnable single-directory bundle (`./AppRun`) |
| `StrawNT-<ver>-x86_64.portable.tar.gz` | Single-file equivalent of AppDir |
| `StrawNT-<ver>-x86_64.AppImage` | Type-2 AppImage (when tool available) |
| `SHA256SUMS` | Checksums (also copied to `tests/portable/output/SHA256SUMS`) |

Evidence: `tests/portable/output/smoke-appimage.json`, `tests/portable/output/SHA256SUMS`.

Do not claim full Windows compatibility in AppImage metadata.
No Wine/Proton substrate; no `WinBox` naming.
