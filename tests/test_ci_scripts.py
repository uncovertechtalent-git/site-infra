"""Tests for the two privacy boundaries of the public CI output: the plan
summary prints counts only, and every private tfvars value gets masked.
Run: python3 -m unittest discover -s tests
"""
import importlib.util
import io
import json
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


summary = load("plan_summary", "scripts/plan_summary.py")
mask = load("tfvars_mask", "scripts/ci/tfvars_mask.py")

SECRET = "private-bucket-name-xyz"
PLAN = {
    "terraform_version": "1.16.4",
    "resource_changes": [
        {"address": f"module.site.aws_s3_bucket.{SECRET}", "mode": "managed", "type": "aws_s3_bucket",
         "change": {"actions": ["create"], "after": {"bucket": SECRET}}},
        {"address": "aws_route53_record.a", "mode": "managed", "type": "aws_route53_record",
         "change": {"actions": ["update"], "before": {"zone_id": "Z123SECRETZONE"}}},
        {"address": "aws_acm_certificate.c", "mode": "managed", "type": "aws_acm_certificate",
         "change": {"actions": ["delete", "create"]}},
        {"address": "aws_iam_role.r", "mode": "managed", "type": "aws_iam_role",
         "change": {"actions": ["no-op"], "importing": {"id": "role-" + SECRET}}},
        {"address": "aws_iam_role.f", "mode": "managed", "type": "aws_iam_role", "change": {"actions": ["forget"]}},
        {"address": "data.aws_s3_bucket.d", "mode": "data", "type": "aws_s3_bucket", "change": {"actions": ["read"]}},
    ],
    "resource_drift": [{"address": "aws_s3_bucket.x", "mode": "managed"}],
}


class PlanSummary(unittest.TestCase):
    def render(self):
        out = io.StringIO()
        stdin, stdout, argv = sys.stdin, sys.stdout, sys.argv
        sys.stdin, sys.stdout = io.StringIO(json.dumps(PLAN)), out
        sys.argv = ["plan_summary.py", "--stack", "example", "--commit", "abc1234"]
        try:
            summary.main()
        finally:
            sys.stdin, sys.stdout, sys.argv = stdin, stdout, argv
        return out.getvalue()

    def test_counts(self):
        text = self.render()
        self.assertIn("1 to create, 1 to update, 1 to replace, 0 to destroy, 1 to import, 1 to forget", text)
        self.assertIn("Refresh: 1 resource(s)", text)

    def test_no_names_ids_or_values(self):
        text = self.render()
        for leak in (SECRET, "Z123SECRETZONE", "module.site", "aws_route53_record.a", "role-"):
            self.assertNotIn(leak, text)


class TfvarsMask(unittest.TestCase):
    TFVARS = '''
aws_account_id    = "123456789012"
state_bucket_name = "site-infra-tfstate-abcdef"
dns_target        = "github_pages"
log_reader_principal_arns = ["arn:aws:iam::123456789012:user/operator"]
sites = {
  "example.org" = {
    repository      = "example/example.org"
    bucket_name     = "examplesitebucket"
    zone_id         = "ZABCDEFGHIJKLMN"
  }
}
'''

    def test_private_values_masked(self):
        values = mask.private_values(self.TFVARS)
        for private in ("123456789012", "site-infra-tfstate-abcdef", "arn:aws:iam::123456789012:user/operator",
                        "examplesitebucket", "ZABCDEFGHIJKLMN"):
            self.assertIn(private, values)

    def test_public_values_stay_readable(self):
        values = mask.private_values(self.TFVARS)
        for public in ("github_pages", "example/example.org", "example.org"):
            self.assertNotIn(public, values)

    def test_cli_prints_mask_commands(self):
        path = ROOT / "tests" / "fixture.tfvars"
        path.write_text(self.TFVARS, encoding="utf-8")
        try:
            out = subprocess.run([sys.executable, str(ROOT / "scripts/ci/tfvars_mask.py"), str(path)],
                                 capture_output=True, text=True, check=True).stdout
        finally:
            path.unlink()
        self.assertIn("::add-mask::examplesitebucket", out)
        self.assertNotIn("github_pages", out)


if __name__ == "__main__":
    unittest.main()
