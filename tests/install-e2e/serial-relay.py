#!/usr/bin/env python3
"""Relay QEMU serial (TCP) to a log file and accept commands via a FIFO."""
from __future__ import annotations

import os
import select
import socket
import sys
import time


def main() -> int:
    if len(sys.argv) != 4:
        print(f"usage: {sys.argv[0]} PORT LOGFILE CMD_FIFO", file=sys.stderr)
        return 2

    port = int(sys.argv[1])
    log_path = sys.argv[2]
    cmd_fifo = sys.argv[3]

    if not os.path.exists(cmd_fifo):
        os.mkfifo(cmd_fifo)

    sock = None
    for _ in range(600):
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=1.0)
            sock.settimeout(1.0)
            break
        except OSError:
            time.sleep(0.25)
    if sock is None:
        print("serial relay could not connect", file=sys.stderr)
        return 1

    try:
        sock.sendall(b"\n")
    except OSError:
        pass

    cmd_fd = os.open(cmd_fifo, os.O_RDWR | os.O_NONBLOCK)

    try:
        with open(log_path, "ab") as logf:
            while True:
                rlist, _, _ = select.select([sock, cmd_fd], [], [], 1.0)
                if sock in rlist:
                    try:
                        data = sock.recv(4096)
                    except (ConnectionResetError, ConnectionAbortedError, OSError):
                        break
                    if not data:
                        break
                    logf.write(data)
                    logf.flush()
                if cmd_fd in rlist:
                    try:
                        cmd = os.read(cmd_fd, 4096)
                    except BlockingIOError:
                        continue
                    if not cmd:
                        continue
                    if not cmd.endswith(b"\n"):
                        cmd += b"\n"
                    sock.sendall(cmd)
    finally:
        os.close(cmd_fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
