/*
 * strawnt_app_stub.exe — NTW5 App Manager lifecycle smoke PE.
 * Staged as catalog exe (line.exe / steam.exe) to prove real install+launch
 * through vendored Wine. Honesty: fixture only — not vendor LINE/Steam UI.
 */
#include <stdio.h>

int main(void) {
    printf("STRAWNT_APPMGR_OK\n");
    fflush(stdout);
    return 0;
}
