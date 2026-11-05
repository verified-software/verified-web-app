#!/usr/bin/env python3
"""Integration tests for the existing forum and tenant-scoped endpoints."""
import http.client
import json
import socket
import subprocess
import sys
import time
import unittest
from pathlib import Path
from urllib.parse import quote

EXECUTABLE = Path(sys.argv.pop(1)).resolve()


class TenantHTTP(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            cls.port = listener.getsockname()[1]
        cls.server = subprocess.Popen([str(EXECUTABLE), str(cls.port)],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if cls.server.poll() is not None:
                raise RuntimeError(cls.server.stderr.read().decode(errors="replace"))
            try:
                with socket.create_connection(("127.0.0.1", cls.port), timeout=0.1):
                    return
            except OSError:
                time.sleep(0.05)
        cls.server.terminate()
        raise RuntimeError("server did not start")

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(timeout=5)
        cls.server.stderr.close()

    def request(self, method, path, body=None, token=None):
        headers = {}
        if token:
            headers["Authorization"] = "Bearer " + token
        if body is not None:
            headers["Content-Type"] = "application/json"
            body = body if isinstance(body, bytes) else json.dumps(body).encode()
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request(method, path, body, headers)
            response = conn.getresponse()
            data = response.read()
            return response.status, json.loads(data)
        finally:
            conn.close()

    def login(self, username):
        status, body = self.request("POST", "/command", {"op":"login", "user":username,
                                                          "password":username+"-demo"})
        self.assertEqual(status, 200)
        return body["token"]

    def test_isolation_and_fail_closed(self):
        alice, bob = self.login("alice"), self.login("bob")
        path = "/tenants/alpha"
        self.assertEqual(self.request("GET", path+"/posts")[0], 401)
        self.assertEqual(self.request("POST", path+"/command", {"op":"create", "body":"x"})[0], 401)
        denied_before = self.request("GET", path+"/posts", token=bob)
        self.assertEqual(denied_before[0], 403)
        status, body = self.request("POST", path+"/command", {"op":"create", "body":"alpha secret"}, alice)
        self.assertEqual((status, body["posts"][0]["body"]), (200,"alpha secret"))
        self.assertEqual(self.request("GET", "/posts")[1], [])
        self.assertEqual(self.request("GET", path+"/posts", token=bob), denied_before)
        self.assertEqual(self.request("POST", path+"/command", {"op":"edit", "id":0, "body":"stolen"}, bob)[0], 403)
        self.assertEqual(self.request("POST", path+"/program", {"budget":1, "program":{"op":"read"}}, bob)[0], 403)
        self.assertEqual(self.request("GET", "/tenants/beta/posts", token=alice)[0], 403)
        self.assertEqual(self.request("POST", "/tenants/beta/command", {"op":"create", "body":"beta"}, bob)[0], 200)
        self.assertEqual(self.request("GET", "/tenants/beta/posts", token=bob)[1][0]["body"], "beta")
        self.assertEqual(self.request("GET", path+"/posts", token=alice)[1][0]["body"], "alpha secret")
        for name in ("a"*33, "Alpha", quote("Ą")):
            self.assertEqual(self.request("GET", "/tenants/"+name+"/posts", token=alice)[0], 400)
        self.assertEqual(self.request("POST", path+"/command", {"op":"read", "tenant":"beta"}, alice)[0], 400)
        self.assertEqual(self.request("POST", path+"/program", {"budget":1,"authority":"alpha", "program":{"op":"read"}}, bob)[0], 400)
        self.assertEqual(self.request("POST", path+"/command", b"x"*4097, alice)[0], 413)
        self.assertEqual(self.request("POST", path+"/program", {"budget":0, "program":{"op":"create", "value":{"text":"x"}}}, alice)[0], 429)
        self.assertEqual(self.request("GET", path+"/posts", token=alice)[1][0]["body"], "alpha secret")
        self.assertEqual(self.request("POST", "/program", {"budget":1,"program":{"op":"restrict"}}, alice)[0], 200)
        self.assertEqual(self.request("GET", path+"/posts", token=alice)[0], 200)
        self.assertEqual(self.request("POST", path+"/command", {"op":"create", "body":"no"}, alice)[0], 403)
        self.assertEqual(self.request("POST", path+"/program", {"budget":1,"program":{"op":"read"}}, alice)[0], 403)
        self.assertEqual(self.request("POST", "/command", {"op":"logout"}, alice)[0], 200)
        self.assertEqual(self.request("GET", path+"/posts", token=alice)[0], 401)


if __name__ == "__main__":
    unittest.main(verbosity=2)
