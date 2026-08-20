"""Run from repo root: python3 tests/test_server_report.py -v"""
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request


class ReportEndpointTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        os.environ["ML_DATA_DIR"] = cls.tmp
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ml"))
        import server  # imported AFTER env var so DATA_DIR picks it up
        cls.server = server
        from http.server import ThreadingHTTPServer
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        cls.port = cls.httpd.server_address[1]
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def _get(self, path):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}") as r:
                return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()

    def test_report_missing_then_present(self):
        code, body = self._get("/report")
        self.assertEqual(code, 404)
        self.assertIn("no report", body)
        with open(os.path.join(self.tmp, "report-latest.txt"), "w") as f:
            f.write("balance report body")
        code, body = self._get("/report")
        self.assertEqual(code, 200)
        self.assertEqual(body, "balance report body")

    def test_history(self):
        with open(os.path.join(self.tmp, "report-history.log"), "w") as f:
            f.write("history body")
        code, body = self._get("/report/history")
        self.assertEqual(code, 200)
        self.assertEqual(body, "history body")

    def test_health_still_works(self):
        code, body = self._get("/health")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body)["status"], "ok")


if __name__ == "__main__":
    unittest.main()
