"""Tests for the visitor classes the site-traffic shipper writes to Loki.
Run: python3 -m unittest discover -s tests
"""
import importlib.util
import json
import os
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
os.environ.setdefault("LOG_BUCKET", "test-bucket")
spec = importlib.util.spec_from_file_location("cloudfront_to_loki", ROOT / "stats/cloudfront_to_loki.py")
shipper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shipper)


class ClassifyAgent(unittest.TestCase):
    def test_own_agents_are_named(self):
        # User-Agents as CloudFront logs them: URL-encoded.
        self.assertEqual(shipper.classify_agent("Mozilla/5.0%20(site-map%20crawler;%20uncovertechtalent)"),
                         ("bot", "site-map-crawler"))
        self.assertEqual(shipper.classify_agent("deploy-exporter"), ("bot", "deploy-exporter"))
        self.assertEqual(shipper.classify_agent("site-infra-parity/1"), ("bot", "site-infra-parity"))
        self.assertEqual(shipper.classify_agent("name-count/1.0%20(site%20owner%20audit)"), ("bot", "name-count"))
        self.assertEqual(shipper.classify_agent("house-portal/0.1"), ("bot", "house-portal"))

    def test_google_fetchers_without_bot_word(self):
        self.assertEqual(shipper.classify_agent("Mozilla/5.0%20(Linux;%20Android%206.0.1;%20Nexus%205X%20Build/MMB29P)"
                                                "%20AppleWebKit/537.36%20(KHTML,%20like%20Gecko)%20Chrome/153.0.8010.52"
                                                "%20Mobile%20Safari/537.36%20(compatible;%20GoogleOther)"),
                         ("bot", "GoogleOther"))

    def test_named_bots_and_humans(self):
        self.assertEqual(shipper.classify_agent("Mozilla/5.0%20AppleWebKit/537.36%20(KHTML,%20like%20Gecko;"
                                                "%20compatible;%20ChatGPT-User/1.0;%20+https://openai.com/bot"),
                         ("bot", "ChatGPT-User"))
        self.assertEqual(shipper.classify_agent("LinkedInBot/1.0%20(compatible;%20Mozilla/5.0)"), ("bot", "LinkedInBot"))
        self.assertEqual(shipper.classify_agent("Mozilla/5.0%20(Macintosh;%20Intel%20Mac%20OS%20X%2010_15_7)"
                                                "%20AppleWebKit/537.36%20(KHTML,%20like%20Gecko)%20Chrome/131.0"),
                         ("human", ""))
        self.assertEqual(shipper.classify_agent("-"), ("bot", "no-user-agent"))
        self.assertEqual(shipper.classify_agent("Mozilla/5.0%20(compatible;%20SomeCrawler/2.0)"), ("bot", "other"))


BROWSER = "Mozilla/5.0%20(Macintosh;%20Intel%20Mac%20OS%20X%2010_15_7)%20AppleWebKit/537.36%20Chrome/149.0.0.0"
SCRIPT = "Mozilla/5.0%20(Windows%20NT%2010.0;%20Win64;%20x64)%20AppleWebKit/537.36%20Chrome/122.0.0.0"


def record(path, time, ua=BROWSER, status="200", ctype="text/html", country="DE"):
    return {"date": "2026-11-24", "time": time, "cs-uri-stem": path, "sc-status": status, "sc-content-type": ctype,
            "cs(User-Agent)": ua, "c-country": country, "x-host-header": "example.org", "cs(Referer)": "-"}


class Rendered(unittest.TestCase):
    def index(self, *records):
        renderers = {}
        for r in records:
            if shipper.render_asset(r) and shipper.classify_agent(r["cs(User-Agent)"])[0] == "human":
                renderers.setdefault(shipper.client_key(r, "example.org"), []).append(shipper.epoch_of(r))
        return {k: sorted(v) for k, v in renderers.items()}

    def line(self, page, renderers):
        return json.loads(shipper.to_line(page, "example.org", renderers)[2])

    def test_page_with_its_stylesheet_is_rendered(self):
        page = record("/a/", "10:00:00")
        r = self.index(page, record("/style.css", "10:00:01", ctype="text/css"))
        self.assertIs(self.line(page, r)["rendered"], True)

    def test_stylesheet_more_than_a_minute_later_does_not_count(self):
        page = record("/d/", "10:00:00")
        self.assertIs(self.line(page, self.index(record("/style.css", "10:01:00", ctype="text/css")))["rendered"], True)
        self.assertIs(self.line(page, self.index(record("/style.css", "10:01:01", ctype="text/css")))["rendered"], False)

    def test_cached_stylesheet_counts_within_the_window(self):
        r = self.index(record("/style.css", "09:40:00", status="304", ctype="text/css"))
        self.assertIs(self.line(record("/b/", "10:00:00"), r)["rendered"], True)
        self.assertIs(self.line(record("/c/", "10:40:00"), r)["rendered"], False)

    def test_html_only_client_is_not_rendered(self):
        r = self.index(record("/style.css", "10:00:01", ctype="text/css"))  # another client's stylesheet
        self.assertIs(self.line(record("/a/", "10:00:00", ua=SCRIPT), r)["rendered"], False)
        self.assertIs(self.line(record("/a/", "10:00:00", country="US"), r)["rendered"], False)

    def test_only_browser_pages_carry_the_field(self):
        r = self.index(record("/style.css", "10:00:01", ctype="text/css"))
        self.assertNotIn("rendered", self.line(record("/style.css", "10:00:01", ctype="text/css"), r))
        self.assertNotIn("rendered", self.line(record("/a/", "10:00:00", ua="LinkedInBot/1.0"), r))


if __name__ == "__main__":
    unittest.main()
