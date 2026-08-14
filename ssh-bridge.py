#!/usr/bin/env python3
"""SSH ProxyCommand bridge: tunnel ssh stdio over the egress HTTP CONNECT proxy."""
import select
import socket
import sys

UPSTREAM = ("127.0.0.1", 18080)
BUFSIZE = 65536


def main():
    host, port = sys.argv[1], sys.argv[2]
    sock = socket.create_connection(UPSTREAM, timeout=20)
    sock.sendall(f"CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        chunk = sock.recv(BUFSIZE)
        if not chunk:
            sys.stderr.write("bridge: proxy closed during CONNECT\n")
            return 1
        resp += chunk
    if not resp.startswith(b"HTTP/1.1 200") and not resp.startswith(b"HTTP/1.0 200"):
        sys.stderr.write(f"bridge: CONNECT failed: {resp!r}\n")
        return 1
    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer
    while True:
        r, _, _ = select.select([sock, stdin], [], [], 30)
        if not r:
            continue
        for src in r:
            data = src.read(BUFSIZE) if src is stdin else src.recv(BUFSIZE)
            if not data:
                sock.close()
                return 0
            if src is stdin:
                sock.sendall(data)
            else:
                stdout.write(data)
                stdout.flush()


if __name__ == "__main__":
    sys.exit(main())
