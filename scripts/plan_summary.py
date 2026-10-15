#!/usr/bin/env python3
"""Summarise a saved Terraform plan as counts, for a public pull request.

Reads `terraform show -json <planfile>` on stdin and prints Markdown: actions
per resource type and in total. It never prints resource names, ids, ARNs,
attribute values or outputs, so the summary is safe to paste anywhere.
"""
import argparse
import collections
import json
import sys

ACTIONS = {
    ("create",): "create",
    ("update",): "update",
    ("delete",): "destroy",
    ("delete", "create"): "replace",
    ("create", "delete"): "replace",
}
COLUMNS = ["create", "update", "replace", "destroy", "import"]


def summarise(plan):
    per_type = collections.defaultdict(collections.Counter)
    for change in plan.get("resource_changes", []):
        if change.get("mode") != "managed":
            continue
        detail = change["change"]
        action = ACTIONS.get(tuple(detail["actions"]))
        if detail.get("importing"):
            per_type[change["type"]]["import"] += 1
        if action:
            per_type[change["type"]][action] += 1
    drift = sum(1 for d in plan.get("resource_drift", []) if d.get("mode") == "managed")
    return per_type, drift


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--stack", required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()

    plan = json.load(sys.stdin)
    per_type, drift = summarise(plan)
    totals = collections.Counter()
    for counts in per_type.values():
        totals.update(counts)

    version = plan.get("terraform_version", "?")
    head = ", ".join(f"{totals[c]} to {c}" for c in COLUMNS)
    print(f"**Plan `{args.stack}`** at `{args.commit}`, Terraform {version}: {head}.")
    if drift:
        print(f"\nDrift: {drift} resource(s) changed outside Terraform since the last apply.")
    if not per_type:
        print("\nNo changes.")
        return
    print()
    print("| Resource type | " + " | ".join(COLUMNS) + " |")
    print("|---|" + "---:|" * len(COLUMNS))
    for rtype in sorted(per_type):
        cells = [str(per_type[rtype][c] or "") for c in COLUMNS]
        print(f"| `{rtype}` | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
