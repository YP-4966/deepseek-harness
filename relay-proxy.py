#!/usr/bin/env python3
"""Minimal HTTP CONNECT relay: forward CONNECT requests to the real egress proxy."""
import socket
import socketserver
import threading

UPSTREAM = ("127.0.0.1", 18080)
LISTEN = ("127.0.0.1", 18082)
BUFSIZE = 65536


def pump(src, dst):
    try:
        while True:
            data = src.recv(BUFSIZE)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        try:
            src.close()
        except OSError:
            pass
        try:
            dst.close()
        except OSError:
            pass


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            first = b""
            while b"\r\n\r\n" not in first:
                chunk = self.request.recv(BUFSIZE)
                if not chunk:
                    return
                first += chunk
                if len(first) > 65536:
                    return
            line = first.split(b"\r\n")[0].decode("latin1", "replace")
            parts = line.split()
            if len(parts) < 2 or parts[0].upper() != "CONNECT":
                self.request.sendall(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
                return
            upstream = socket.create_connection(UPSTREAM, timeout=15)
            upstream.sendall(first)
            resp = b""
            while b"\r\n\r\n" not in resp:
                chunk = upstream.recv(BUFSIZE)
                if not chunk:
                    break
                resp += chunk
            if not resp.startswith(b"HTTP/1.1 200") and not resp.startswith(b"HTTP/1.0 200"):
                self.request.sendall(resp or b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
                upstream.close()
                return
            self.request.sendall(resp)
            threading.Thread(target=pump, args=(self.request, upstream), daemon=True).start()
            pump(upstream, self.request)
        except Exception:
            try:
                self.request.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            except OSError:
                pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    Server(LISTEN, Handler).serve_forever()
