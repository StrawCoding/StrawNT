/*
 * strawnt_ac_stub.exe — anti-cheat companion stand-in (NTW4).
 * Modes: named pipe listen (same_prefix) | broker TCP recv/send (cross_prefix).
 * Honesty: fixture only — not a vendor anti-cheat.
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
    fprintf(stderr, "ac_stub FAIL: %s\n", msg);
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

static int pipe_listen(const char *name, const char *expect, DWORD timeout_ms) {
    char path[256];
    snprintf(path, sizeof(path), "\\\\.\\pipe\\%s", name);
    HANDLE h = CreateNamedPipeA(
        path,
        PIPE_ACCESS_INBOUND,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
        1, 4096, 4096, timeout_ms, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "CreateNamedPipe failed gle=%lu\n", GetLastError());
        return 1;
    }
    printf("ac_stub: pipe listening %s\n", path);
    fflush(stdout);
    if (!ConnectNamedPipe(h, NULL)) {
        DWORD e = GetLastError();
        if (e != ERROR_PIPE_CONNECTED) {
            fprintf(stderr, "ConnectNamedPipe failed gle=%lu\n", e);
            CloseHandle(h);
            return 1;
        }
    }
    char buf[4096];
    DWORD n = 0;
    if (!ReadFile(h, buf, sizeof(buf) - 1, &n, NULL)) {
        fprintf(stderr, "ReadFile failed gle=%lu\n", GetLastError());
        CloseHandle(h);
        return 1;
    }
    buf[n] = 0;
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r' || buf[n - 1] == 0)) {
        buf[--n] = 0;
    }
    printf("ac_stub: received '%s'\n", buf);
    fflush(stdout);
    CloseHandle(h);
    if (strcmp(buf, expect) != 0) {
        fprintf(stderr, "payload mismatch want='%s'\n", expect);
        return 1;
    }
    printf("ac_stub PASS pipe %s\n", expect);
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
    snprintf(line, sizeof(line), "AUTH %s %s ac %s\n", token, prefix_id, channel);
    if (send(s, line, (int)strlen(line), 0) <= 0) die("send AUTH");
    if (readline_sock(s, line, sizeof(line)) < 0) die("recv AUTH");
    if (strcmp(line, "OK AUTH") != 0) {
        fprintf(stderr, "AUTH failed: %s\n", line);
        closesocket(s);
        WSACleanup();
        return 1;
    }

    if (role && strcmp(role, "send") == 0) {
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
        printf("ac_stub PASS broker send %s\n", send_payload);
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
        printf("ac_stub: broker received '%s'\n", payload);
        fflush(stdout);
        if (expect && strcmp(payload, expect) != 0) {
            fprintf(stderr, "payload mismatch want='%s'\n", expect);
            closesocket(s);
            WSACleanup();
            return 1;
        }
        printf("ac_stub PASS broker %s\n", payload);
    }

    send(s, "QUIT\n", 5, 0);
    closesocket(s);
    WSACleanup();
    fflush(stdout);
    return 0;
}

int main(int argc, char **argv) {
    const char *mode = get_opt(argc, argv, "--mode", "pipe");
    const char *role = get_opt(argc, argv, "--role", "listen");
    const char *pipe_name = get_opt(argc, argv, "--pipe", "strawnt-ntw4-same");
    const char *expect = get_opt(argc, argv, "--expect", "STRAWNT_NTW4_SAME");
    const char *sendp = get_opt(argc, argv, "--send", NULL);
    const char *host = get_opt(argc, argv, "--host", "127.0.0.1");
    const char *port_s = get_opt(argc, argv, "--port", "17864");
    const char *token = get_opt(argc, argv, "--token", "");
    const char *prefix_id = get_opt(argc, argv, "--prefix-id", "pfx-ac");
    const char *channel = get_opt(argc, argv, "--channel", "ntw4-cross");
    const char *timeout_s = get_opt(argc, argv, "--timeout-ms", "15000");
    DWORD timeout_ms = (DWORD)strtoul(timeout_s, NULL, 10);
    int port = atoi(port_s);

    if (strcmp(mode, "pipe") == 0) {
        if (strcmp(role, "listen") != 0 && strcmp(role, "recv") != 0) {
            die("pipe mode expects --role listen");
        }
        return pipe_listen(pipe_name, expect, timeout_ms);
    }
    if (strcmp(mode, "broker") == 0) {
        return broker_mode(host, port, token, prefix_id, channel, role, sendp, expect, timeout_ms);
    }
    die("unknown --mode (pipe|broker)");
    return 1;
}
