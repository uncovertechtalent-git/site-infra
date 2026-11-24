"""Tests for the visitor classes the site-traffic shipper writes to Loki.
Run: python3 -m unittest discover -s tests
"""
import importlib.util
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


if __name__ == "__main__":
    unittest.main()
