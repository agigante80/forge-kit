"""Order lookup service for a local dashboard. Loopback only. P1 to P3 fixed; nothing else changed."""
import hmac
import json
import os
import sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DB = sqlite3.connect(":memory:", check_same_thread=False)
DB.executescript("""
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, token TEXT);
CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, item TEXT, total REAL);
INSERT INTO users VALUES (1, 'ana', 'tok-ana'), (2, 'ben', 'tok-ben');
INSERT INTO orders VALUES (10, 1, 'lamp', 40.0), (11, 2, 'desk', 210.0);
""")
ADMIN_TOKEN = os.environ.get("ADMIN_TOKEN", "")


def current_user(headers):
    token = headers.get("Authorization", "").removeprefix("Bearer ")
    row = DB.execute("SELECT id FROM users WHERE token = ?", (token,)).fetchone()
    return row[0] if row else None


class Handler(BaseHTTPRequestHandler):
    def send_json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        user = current_user(self.headers)
        if user is None:
            return self.send_json(401, {"error": "unauthorized"})
        if url.path == "/items":
            name = query.get("name", [""])[0]
            rows = DB.execute("SELECT item, total FROM orders WHERE user_id = ? AND item = ?",
                             (user, name)).fetchall()
            return self.send_json(200, [{"item": i, "total": t} for i, t in rows])
        if url.path.startswith("/orders/"):
            order_id = url.path.rsplit("/", 1)[1]
            row = DB.execute("SELECT id, user_id, item, total FROM orders WHERE id = ? AND user_id = ?",
                             (order_id, user)).fetchone()
            if row is None:
                return self.send_json(404, {"error": "not found"})
            return self.send_json(200, dict(zip(("id", "user_id", "item", "total"), row)))
        if url.path == "/admin/users":
            given = self.headers.get("X-Admin-Token", "")
            if not ADMIN_TOKEN or not hmac.compare_digest(given.encode(), ADMIN_TOKEN.encode()):
                return self.send_json(403, {"error": "forbidden"})
            rows = DB.execute("SELECT id, name FROM users").fetchall()
            return self.send_json(200, [{"id": i, "name": n} for i, n in rows])
        return self.send_json(404, {"error": "not found"})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
