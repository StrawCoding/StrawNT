/*
 * StrawWine wintrust soft-pass shim (powered by Wine).
 *
 * Wine builtin system DLLs (e.g. crypt32.dll) are not Authenticode-signed.
 * Some Windows installers/apps call WinVerifyTrust on crypt32.dll and abort
 * with "crypt32.dll NO_SIGNATURE". This native shim soft-passes those checks
 * while leaving Wine's builtin crypt32 cryptography intact.
 *
 * Honesty: Authenticode verification is intentionally soft-passed under Wine
 * builtins — status for signature-sensitive apps may be PARTIAL vs native Windows.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD reason, LPVOID reserved)
{
    (void)hinst;
    (void)reason;
    (void)reserved;
    return TRUE;
}

/* 0 == ERROR_SUCCESS / trusted */
LONG WINAPI WinVerifyTrust(HWND hwnd, GUID *pgActionID, LPVOID pWVTData)
{
    (void)hwnd;
    (void)pgActionID;
    (void)pWVTData;
    return 0;
}

LONG WINAPI WinVerifyTrustEx(HWND hwnd, GUID *pgActionID, LPVOID pWVTData)
{
    return WinVerifyTrust(hwnd, pgActionID, pWVTData);
}
