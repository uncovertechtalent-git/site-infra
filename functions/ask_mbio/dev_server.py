#!/usr/bin/env python3
"""Local preview of the ask mbio MCP server: the Lambda handler behind a plain HTTP server on 127.0.0.1.

    ASK_SITE=http://127.0.0.1:8000 python3 functions/ask_mbio/dev_server.py [--port 8787]
    claude mcp add --transport http ask-mbio-preview http://127.0.0.1:8787/mcp

ASK_SITE is where the published files are read from: the live site by default, or a local copy of a site build
served with `python3 -m http.server 8000`. Each request becomes a function URL event (payload 2.0), as on Lambda.
"""
import argparse, base64, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import handler  # noqa: E402


class Dev(BaseHTTPRequestHandler):
    def _serve(self):
        try:
            n = max(0, min(int(self.headers.get('Content-Length') or 0), handler.MAX_BODY * 2))
        except ValueError:
            n = 0
        body = self.rfile.read(n) if n else b''
        event = {
            'rawPath': self.path.split('?', 1)[0],
            'headers': {k.lower(): v for k, v in self.headers.items()},
            'requestContext': {'http': {'method': self.command, 'path': self.path.split('?', 1)[0]}},
            'body': base64.b64encode(body).decode('ascii'),
            'isBase64Encoded': True,
        }
        resp = handler.handle_http(event)
        out = resp['body'].encode('utf-8') if isinstance(resp['body'], str) else resp['body']
        self.send_response(resp['statusCode'])
        for k, v in resp['headers'].items():
            self.send_header(k, v)
        self.send_header('Content-Length', str(len(out)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(out)

    do_GET = do_POST = do_DELETE = do_HEAD = do_OPTIONS = _serve

    def log_message(self, *a):  # the handler logs one counts-only line per request; no access log with addresses
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=8787)
    port = ap.parse_args().port
    print(f'ask mbio preview on http://127.0.0.1:{port}/mcp, reading {handler.SITE}', file=sys.stderr)
    HTTPServer(('127.0.0.1', port), Dev).serve_forever()  # one request at a time, like one Lambda instance


if __name__ == '__main__':
    main()
