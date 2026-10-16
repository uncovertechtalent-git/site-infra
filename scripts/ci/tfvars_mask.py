#!/usr/bin/env python3
"""Print a GitHub ::add-mask:: line for every private value in a tfvars file.

Every quoted string of four or more characters on the right of `key =` is
private, unless the key is on the public list (host names, repository names,
switches). Map keys such as "example.org" = { ... } are not values. List and
map values on the following lines of a multi-line value inherit their key.
Usage: tfvars_mask.py <file.tfvars>
"""
import re
import sys

PUBLIC_KEYS = {"dns_target", "repository", "github_repository", "apply_environment", "region"}
ASSIGN = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")
QUOTED = re.compile(r'"([^"]{4,})"')


def private_values(text):
    values, key = set(), None
    for line in text.splitlines():
        line = line.split("#", 1)[0]
        match = ASSIGN.match(line)
        if match:
            key, rest = match.group(1), match.group(2)
        elif re.match(r'^\s*"[^"]*"\s*=', line):
            key, rest = None, line.split("=", 1)[1]  # a map key line: its value follows
        else:
            rest = line
        if key in PUBLIC_KEYS:
            continue
        values.update(QUOTED.findall(rest))
    return sorted(values)


def main():
    with open(sys.argv[1], encoding="utf-8") as fh:
        for value in private_values(fh.read()):
            print(f"::add-mask::{value}")


if __name__ == "__main__":
    main()
