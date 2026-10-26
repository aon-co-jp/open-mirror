#!/usr/bin/env python3
"""webpage/ を静的配信する。http.server と違い、/demo のように末尾スラッシュ無しで
ディレクトリが指定されても、/demo/ へ転送せずそのまま index.html を返す。
(open-web-server の strip_prefix 経由だと、転送先からパス接頭辞が消えてしまうため)

使い方 / usage: python3 serve-static.py <ポート> <ディレクトリ>
"""
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        self._fix()
        super().do_GET()

    def do_HEAD(self):
        self._fix()
        super().do_HEAD()

    def _fix(self):
        path, sep, query = self.path.partition("?")
        if not path.endswith("/") and os.path.isdir(self.translate_path(path)):
            self.path = path + "/" + (sep + query if sep else "")


if __name__ == "__main__":
    port = int(sys.argv[1])
    root = os.path.abspath(sys.argv[2])
    handler = lambda *a, **k: Handler(*a, directory=root, **k)
    ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
