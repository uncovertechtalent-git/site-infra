#!/usr/bin/env python3
"""Compare a candidate host with the live site, page by page.

Fetches every URL in the reference sitemap plus a few fixed probes (redirects,
the 404 page, plain files) from both hosts and compares status, Location,
Content-Type, Cache-Control, the body (sha256) and the canonical link. On the
candidate it also checks the security headers. Prints a Markdown report and
exits 1 on any mismatch in status, Location, canonical link or headers.

--connect-to sends the candidate's requests to another address with the
candidate host name for TLS and Host, the way curl --connect-to does. That
tests the canonical host on CloudFront before DNS moves:

  parity.py --reference https://example.org \\
            --candidate https://example.org --connect-to d111111abcdef8.cloudfront.net

Standard library only.
"""
import argparse
import concurrent.futures
import hashlib
import http.client
import re
import socket
import ssl
import sys
import urllib.parse
import xml.etree.ElementTree as ET

SECURITY_HEADERS = [
    "strict-transport-security",
    "x-content-type-options",
    "x-frame-options",
    "referrer-policy",
    "permissions-policy",
]
FIXED_PROBES = ["/", "/sitemap.xml", "/robots.txt", "/llms.txt", "/404.html", "/parity-probe-missing/", "/parity-probe-missing.css"]
CANONICAL = re.compile(rb'<link[^>]+rel=["\']canonical["\'][^>]*>', re.I)
HREF = re.compile(rb'href=["\']([^"\']+)["\']', re.I)


class Client:
    def __init__(self, base, connect_to=None):
        parts = urllib.parse.urlsplit(base)
        self.host = parts.hostname
        self.address = connect_to or self.host
        self.context = ssl.create_default_context()

    def get(self, path):
        sock = socket.create_connection((self.address, 443), timeout=20)
        tls = self.context.wrap_socket(sock, server_hostname=self.host)
        conn = http.client.HTTPSConnection(self.host, timeout=20, context=self.context)
        conn.sock = tls
        try:
            conn.request("GET", path, headers={
                "Host": self.host,
                "Accept-Encoding": "identity",
                "User-Agent": "site-infra-parity/1",
            })
            resp = conn.getresponse()
            body = resp.read()
            headers = {k.lower(): v for k, v in resp.getheaders()}
            return resp.status, headers, body
        finally:
            conn.close()


def canonical(body):
    match = CANONICAL.search(body)
    if not match:
        return None
    href = HREF.search(match.group(0))
    return href.group(1).decode() if href else None


def sitemap_paths(client):
    status, _, body = client.get("/sitemap.xml")
    if status != 200:
        raise SystemExit(f"reference sitemap answered {status}")
    root = ET.fromstring(body)
    paths = []
    for loc in root.iter("{http://www.sitemaps.org/schemas/sitemap/0.9}loc"):
        path = urllib.parse.urlsplit(loc.text.strip()).path or "/"
        paths.append(path)
    return paths


def redirect_probes(paths):
    # A directory page without its trailing slash must answer 301 on both hosts.
    probes = [p.rstrip("/") for p in paths if p.endswith("/") and p != "/"]
    return probes[:5]


def compare(path, ref, cand, ref_host, cand_host):
    r_status, r_head, r_body = ref.get(path)
    c_status, c_head, c_body = cand.get(path)
    issues, notes = [], []
    if r_status != c_status:
        issues.append(f"status {r_status} vs {c_status}")
    r_loc = r_head.get("location", "").replace(f"//{ref_host}", f"//{cand_host}")
    if r_loc != c_head.get("location", ""):
        issues.append(f"location {r_head.get('location')} vs {c_head.get('location')}")
    if r_head.get("content-type") != c_head.get("content-type"):
        issues.append(f"content-type {r_head.get('content-type')} vs {c_head.get('content-type')}")
    if r_status == 200 and r_head.get("cache-control") != c_head.get("cache-control"):
        issues.append(f"cache-control {r_head.get('cache-control')} vs {c_head.get('cache-control')}")
    if r_status == 200 and (c_head.get("content-type") or "").startswith("text/html"):
        if canonical(r_body) != canonical(c_body):
            issues.append(f"canonical {canonical(r_body)} vs {canonical(c_body)}")
    if c_status < 300 or c_status >= 400:
        missing = [h for h in SECURITY_HEADERS if h not in c_head]
        if missing:
            issues.append("missing " + ", ".join(missing))
    same_body = hashlib.sha256(r_body).digest() == hashlib.sha256(c_body).digest()
    if r_status == 200 and not same_body:
        notes.append("body differs")
    return path, r_status, c_status, issues, notes


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--reference", required=True, help="live site, for example https://example.org")
    parser.add_argument("--candidate", required=True, help="host under test, for example https://next.example.org")
    parser.add_argument("--connect-to", help="address to send the candidate's requests to")
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()

    ref = Client(args.reference)
    cand = Client(args.candidate, args.connect_to)
    paths = sitemap_paths(ref)
    probes = sorted(set(paths + FIXED_PROBES + redirect_probes(paths)))

    with concurrent.futures.ThreadPoolExecutor(args.workers) as pool:
        results = list(pool.map(lambda p: compare(p, ref, cand, ref.host, cand.host), probes))

    failed = [r for r in results if r[3]]
    differing = [r for r in results if r[4]]
    statuses = {}
    for _, r_status, c_status, _, _ in results:
        statuses[c_status] = statuses.get(c_status, 0) + 1

    via = f" via {args.connect_to}" if args.connect_to else ""
    print(f"**Parity** {args.candidate}{via} against {args.reference}: {len(probes)} URLs "
          f"({len(paths)} from the sitemap), {len(results) - len(failed)} match, {len(failed)} mismatch, "
          f"{len(differing)} with a different body.")
    print("Candidate status codes: " + ", ".join(f"{k}: {v}" for k, v in sorted(statuses.items())) + ".")
    if failed:
        print("\n| Path | Reference | Candidate | Mismatch |\n|---|---:|---:|---|")
        for path, r_status, c_status, issues, _ in sorted(failed):
            print(f"| `{path}` | {r_status} | {c_status} | {'; '.join(issues)} |")
    if differing:
        print("\nBodies that differ (same status and headers):")
        for path, *_ in sorted(differing)[:40]:
            print(f"- `{path}`")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
