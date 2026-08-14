#!/usr/bin/env python3
"""Diagnose localtunnel protocol over the egress HTTP CONNECT proxy."""
import hashlib
import json
import socket
import ssl
import sys
import base64

PROXY = ("127.0.0.1", 18080)
API_HOST = "localtunnel.me"
API_PORT = 443
BUFSIZE = 65536


def connect_tunnel(host, port):
    sock = socket.create_connection(PROXY, timeout=20)
    sock.sendall(f"CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        chunk = sock.recv(BUFSIZE)
        if not chunk:
            raise RuntimeError("proxy closed during CONNECT")
        resp += chunk
    if not resp.startswith(b"HTTP/1.1 200") and not resp.startswith(b"HTTP/1.0 200"):
        raise RuntimeError(f"CONNECT failed: {resp[:200]!r}")
    ctx = ssl.create_default_context()
    return ctx.wrap_socket(sock, server_hostname=host)


def read_headers(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(BUFSIZE)
        if not chunk:
            break
        data += chunk
    return data


def get_tunnel_id():
    conn = connect_tunnel(API_HOST, API_PORT)
    conn.sendall(b"GET /?new=1 HTTP/1.1\r\nHost: localtunnel.me\r\nConnection: close\r\n\r\n")
    data = read_headers(conn)
    # split headers from body
    head, sep, body = data.partition(b"\r\n\r\n")
    if not body:
        conn.settimeout(5)
        try:
            while True:
                chunk = conn.recv(BUFSIZE)
                if not chunk:
                    break
                body += chunk
        except socket.timeout:
            pass
    conn.close()
    print("=== API response headers ===")
    print(head.decode("latin1", "replace"))
    print("=== API body ===")
    print(body.decode("latin1", "replace"))
    info = json.loads(body)
    return info["id"], info["url"], info["port"]


def main():
    tunnel_id, url, port = get_tunnel_id()
    print(f"\n=== tunnel id={tunnel_id} url={url} port={port} ===")
    from urllib.parse import urlparse
    parsed = urlparse(url)
    host = parsed.hostname
    key = base64.b64encode(hashlib.sha1(tunnel_id.encode()).digest()).decode()
    req = (
        f"GET /?id={tunnel_id} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"User-Agent: localtunnel/3.0.1\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"\r\n"
    )
    conn = connect_tunnel(host, port)
    conn.sendall(req.encode())
    conn.settimeout(20)
    resp = read_headers(conn)
    print("=== upgrade response (first 2000 bytes) ===")
    print(resp[:2000].decode("latin1", "replace"))
    status = resp.split(b"\r\n", 1)[0]
    if b"101" in status:
        print("\n=== SUCCESS: got 101, tunnel established ===")
        # send a sample HTTP request through the tunnel to local backend
        sample = (
            b"GET / HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"\r\n"
        )
        conn.sendall(sample)
        time.sleep(5)
        print("=== local backend response ===")
        print(conn.recv(BUFSIZE).decode("latin1", "replace"))
    else:
        print("\n=== FAILED: no 101 ===")
    conn.close()


if __name__ == "__main__":
    import time
    main()
