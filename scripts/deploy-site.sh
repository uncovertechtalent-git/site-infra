#!/usr/bin/env bash
# Publish a built site directory to its bucket, then invalidate the distribution.
# The site repository's deploy job runs it with the OIDC deploy role; the
# operator host runs it by hand for the first sync and for parity checks.
#
# Content types and Cache-Control match what GitHub Pages sends today, so the
# cutover changes the host, not the responses. Text types carry charset=utf-8.
# Every deploy invalidates /*, so the edge never serves a page older than the deploy.
#
# Usage: scripts/deploy-site.sh <site-dir> <bucket> <distribution-id>
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <site-dir> <bucket> <distribution-id>" >&2
  exit 2
fi
src="${1%/}" bucket="$2" distribution="$3"
[ -f "$src/index.html" ] || { echo "no index.html in $src" >&2; exit 2; }

cache_control="public, max-age=600"
exclude=(--exclude ".git/*" --exclude ".github/*" --exclude "CNAME" --exclude ".nojekyll")

# Filters apply in order, the last match wins: the excludes come after each include.
# Extension -> Content-Type, where the guess from the extension differs from GitHub Pages.
types=(
  "html|text/html; charset=utf-8"
  "css|text/css; charset=utf-8"
  "js|application/javascript; charset=utf-8"
  "mjs|application/javascript; charset=utf-8"
  "json|application/json; charset=utf-8"
  "txt|text/plain; charset=utf-8"
  "md|text/markdown; charset=utf-8"
  "csv|text/csv; charset=utf-8"
  "xml|application/xml"
  "svg|image/svg+xml"
  "yml|text/yaml"
  "yaml|text/yaml"
  "jsonl|application/octet-stream"
  "py|application/octet-stream"
)

for entry in "${types[@]}"; do
  ext="${entry%%|*}" content_type="${entry#*|}"
  aws s3 sync "$src" "s3://$bucket" --only-show-errors \
    --exclude "*" --include "*.$ext" "${exclude[@]}" \
    --content-type "$content_type" --cache-control "$cache_control"
done

# Everything else, with the type guessed from the extension. --delete removes
# objects that the build no longer has; files uploaded above are not sent again.
aws s3 sync "$src" "s3://$bucket" --only-show-errors --delete "${exclude[@]}" \
  --cache-control "$cache_control"

invalidation=$(aws cloudfront create-invalidation --distribution-id "$distribution" \
  --paths "/*" --query "Invalidation.Id" --output text)
echo "synced; invalidation $invalidation"
