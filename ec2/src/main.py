from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import os
import time


class Handler(BaseHTTPRequestHandler):
    server_version = "HttpTrafficLab/1.0"

    def log_message(self, fmt, *args):
        print(
            "%s - - [%s] %s"
            % (
                self.client_address[0],
                self.log_date_time_string(),
                fmt % args,
            ),
            flush=True,
        )

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/download":
            qs = parse_qs(parsed.query)

            mb = int(qs.get("mb", ["1"])[0])
            mb = max(1, min(mb, 1024))

            size = mb * 1024 * 1024

            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(size))
            self.end_headers()

            chunk = b"x" * (1024 * 1024)

            for _ in range(mb):
                self.wfile.write(chunk)

            return

        body = b"ok\n"

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))

        remaining = length
        received = 0
        start = time.time()

        while remaining > 0:
            chunk = self.rfile.read(min(1024 * 1024, remaining))

            if not chunk:
                break

            received += len(chunk)
            remaining -= len(chunk)

        elapsed = max(time.time() - start, 0.000001)
        mb = received / 1024 / 1024
        mbps = mb / elapsed

        self.send_response(204)
        self.send_header("X-Received-MB", f"{mb:.3f}")
        self.send_header("X-Receive-MBps", f"{mbps:.3f}")
        self.end_headers()


def main():
    port = int(os.environ.get("HTTP_PORT", "8000"))

    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)

    print(f"HTTP traffic server is running on port {port}", flush=True)

    server.serve_forever()


if __name__ == "__main__":
    main()