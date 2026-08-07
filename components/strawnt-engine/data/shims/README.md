# StrawNT wintrust soft-pass shims

Prebuilt `wintrust_*.dll` used by recipe `crypt32-signature` (merged from
straw-wine policy C).

Wine builtin system DLLs are not Authenticode-signed. Apps that
`WinVerifyTrust` crypt32.dll (notably LINE Desktop `verifyCodeSign`) abort
with signature failures. These native shims soft-pass those checks while
keeping Wine's builtin crypt32 cryptography.

Honesty: Authenticode soft-pass under Wine builtins — PARTIAL vs native
Windows signature validation. Not a ranked / official anti-cheat claim.

Rebuild from `components/strawnt-engine/shims/build_shims.sh` if needed.
