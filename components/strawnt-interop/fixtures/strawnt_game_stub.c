/*
 * strawnt_game_stub.exe — game stand-in (NTW4).
 * Modes: named pipe connect/send (same_prefix) | broker TCP send/recv (cross_prefix).
 * Honesty: fixture only — not a real game or anti-cheat client.
 */
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "ws2_32.lib")

static void die(const char *msg) {
    fprintf(stderr, "game_stub FAIL: %s\n", msg);
    fflush(stderr);
    ExitProcess(1);
}

static int arg_eq(const char *a, const char *b) { return strcmp(a, b) == 0; }

static const char *get_opt(int argc, char **argv, const char *key, const char *defv) {
    for (int i = 1; i + 1 < argc; i++) {
        if (arg_eq(argv[i], key)) return argv[i + 1];
    }
    return defv;
}

static int pipe_connect(const char *name, const char *payload, DWORD timeout_ms) {
    char path[256];
    snprintf(path, sizeof(path), "\\\\.\\pipe\\%s", name);
    DWORD start = GetTickCount();
    HANDLE h = INVALID_HANDLE_VALUE;
    for (;;) {
        h = CreateFileA(path, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
        if (h != INVALID_HANDLE_VALUE) break;
        DWORD e = GetLastError();
        if (e != ERROR_PIPE_BUSY && e != ERROR_FILE_NOT_FOUND) {
            fprintf(stderr, "CreateFile pipe failed gle=%lu\n", e);
            return 1;
        }
        if (GetTickCount() - start > timeout_ms) {
            fprintf(stderr, "pipe connect timeout\n");
            return 1;
        }
        WaitNamedPipeA(path, 500);
        Sleep(50);
    }
    DWORD written = 0;
    if (!WriteFile(h, payload, (DWORD)strlen(payload), &written, NULL)) {
        fprintf(stderr, "WriteFile failed gle=%lu\n", GetLastError());
        CloseHandle(h);
        return 1;
    }
    FlushFileBuffers(h);
    CloseHandle(h);
    printf("game_stub PASS pipe send %s\n", payload);
    fflush(stdout);
    return 0;
}

static int readline_sock(SOCKET s, char *buf, int cap) {
    int n = 0;
    while (n + 1 < cap) {
        char c;
        int r = recv(s, &c, 1, 0);
        if (r <= 0) return -1;
        if (c == '\n') break;
        if (c == '\r') continue;
        buf[n++] = c;
    }
    buf[n] = 0;
    return n;
}

static int broker_mode(const char *host, int port, const char *token, const char *prefix_id,
                       const char *channel, const char *role, const char *send_payload,
                       const char *expect, DWORD timeout_ms) {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) die("WSAStartup");

    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) die("socket");

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((u_short)port);
    if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) die("inet_pton");
    if (connect(s, (struct sockaddr *)&addr, sizeof(addr)) != 0) die("connect");

    char line[4600];
    snprintf(line, sizeof(line), "AUTH %s %s game %s\n", token, prefix_id, channel);
    if (send(s, line, (int)strlen(line), 0) <= 0) die("send AUTH");
    if (readline_sock(s, line, sizeof(line)) < 0) die("recv AUTH");
    if (strcmp(line, "OK AUTH") != 0) {
        fprintf(stderr, "AUTH failed: %s\n", line);
        closesocket(s);
        WSACleanup();
        return 1;
    }

    if (!role || strcmp(role, "recv") != 0) {
        if (!send_payload) die("send role needs --send");
        snprintf(line, sizeof(line), "SEND %s\n", send_payload);
        if (send(s, line, (int)strlen(line), 0) <= 0) die("send SEND");
        if (readline_sock(s, line, sizeof(line)) < 0) die("recv SEND");
        if (strcmp(line, "OK SEND") != 0) {
            fprintf(stderr, "SEND failed: %s\n", line);
            closesocket(s);
            WSACleanup();
            return 1;
        }
        printf("game_stub PASS broker send %s\n", send_payload);
    } else {
        snprintf(line, sizeof(line), "RECV %lu\n", (unsigned long)timeout_ms);
        if (send(s, line, (int)strlen(line), 0) <= 0) die("send RECV");
        if (readline_sock(s, line, sizeof(line)) < 0) die("recv DATA");
        if (strncmp(line, "DATA ", 5) != 0) {
            fprintf(stderr, "RECV failed: %s\n", line);
            closesocket(s);
            WSACleanup();
            return 1;
        }
        const char *payload = line + 5;
        printf("game_stub: broker received '%s'\n", payload);
        if (expect && strcmp(payload, expect) != 0) {
            fprintf(stderr, "payload mismatch want='%s'\n", expect);
            closesocket(s);
            WSACleanup();
            return 1;
        }
        printf("game_stub PASS broker %s\n", payload);
    }

    send(s, "QUIT\n", 5, 0);
    closesocket(s);
    WSACleanup();
    fflush(stdout);
    return 0;
}

int main(int argc, char **argv) {
    const char *mode = get_opt(argc, argv, "--mode", "pipe");
    const char *role = get_opt(argc, argv, "--role", "connect");
    const char *pipe_name = get_opt(argc, argv, "--pipe", "strawnt-ntw4-same");
    const char *sendp = get_opt(argc, argv, "--send", "STRAWNT_NTW4_SAME");
    const char *expect = get_opt(argc, argv, "--expect", NULL);
    const char *host = get_opt(argc, argv, "--host", "127.0.0.1");
    const char *port_s = get_opt(argc, argv, "--port", "17864");
    const char *token = get_opt(argc, argv, "--token", "");
    const char *prefix_id = get_opt(argc, argv, "--prefix-id", "pfx-game");
    const char *channel = get_opt(argc, argv, "--channel", "ntw4-cross");
    const char *timeout_s = get_opt(argc, argv, "--timeout-ms", "15000");
    DWORD timeout_ms = (DWORD)strtoul(timeout_s, NULL, 10);
    int port = atoi(port_s);

    if (strcmp(mode, "pipe") == 0) {
        return pipe_connect(pipe_name, sendp, timeout_ms);
    }
    if (strcmp(mode, "broker") == 0) {
        return broker_mode(host, port, token, prefix_id, channel, role, sendp, expect, timeout_ms);
    }
    die("unknown --mode (pipe|broker)");
    return 1;
}
