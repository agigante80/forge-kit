"""Answer key for the tier-probe-security-tester fixture. Never copied into a run directory.

Starts the server named by SERVER_FILE (default server.py, resolved beside this file) on
127.0.0.1:8765 and asserts each planted issue has a black-box witness. Against server.py all
three tests fail; against server_fixed.py all three pass.
"""
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
SERVER_FILE = HERE / os.environ.get("SERVER_FILE", "server.py")
BASE = "http://127.0.0.1:8765"


@pytest.fixture(scope="module", autouse=True)
def server():
    with socket.socket() as probe:
        probe.settimeout(0.5)
        if probe.connect_ex(("127.0.0.1", 8765)) == 0:
            raise RuntimeError("port 8765 is already in use; stop whatever listens there first")
    proc = subprocess.Popen([sys.executable, str(SERVER_FILE)], cwd=HERE)
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(BASE, timeout=0.5)
            except urllib.error.HTTPError:
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("server did not start on 127.0.0.1:8765")
        # The probe above only sees a listener that exists before it runs. The readiness loop
        # accepts any HTTP error response (such as any 4xx or 5xx), so a listener that appears
        # after the probe (a concurrent run) can answer for a child that lost the bind and exits
        # at once. poll() would run before that child has exited, so wait briefly for it
        # instead (#355).
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        else:
            raise RuntimeError("server process exited during startup")
        yield
    finally:
        proc.terminate()
        proc.wait(timeout=5)


def get(path, token):
    req = urllib.request.Request(BASE + path, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read())


def test_p1_sqli_in_items_name_returns_nothing():
    # positive direction, holds on both servers: a real item name returns that row
    status, body = get("/items?name=lamp", "tok-ana")
    assert (status, body) == (200, [{"item": "lamp", "total": 40.0}])
    status, body = get("/items?name=" + urllib.parse.quote("x' OR '1'='1"), "tok-ana")
    assert (status, body) == (200, [])


def test_p2_bola_ana_cannot_read_bens_order():
    # positive direction, holds on both servers: ana reads her own order
    status, body = get("/orders/10", "tok-ana")
    assert status == 200 and body["user_id"] == 1
    status, _ = get("/orders/11", "tok-ana")
    assert status == 404


def test_p3_bfla_ben_cannot_read_admin_users():
    # positive direction, holds on both servers: admin ana reads the list
    status, _ = get("/admin/users", "tok-ana")
    assert status == 200
    status, _ = get("/admin/users", "tok-ben")
    assert status == 403
