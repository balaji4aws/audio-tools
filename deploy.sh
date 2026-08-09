#!/usr/bin/env bash
# Redeploy Audio Clip & Combine: upload the static files and refresh CloudFront.
# Reads bucket/distribution info from .deploy-info (created at first deploy).
set -e
cd "$(dirname "$0")"

if [ ! -f .deploy-info ]; then
  echo "Missing .deploy-info — can't find the target bucket/distribution." >&2
  exit 1
fi
# shellcheck disable=SC1091
source .deploy-info

echo "Uploading files to s3://$BUCKET ..."
aws s3 cp index.html  "s3://$BUCKET/index.html"  --content-type "text/html; charset=utf-8"       --profile "$PROFILE" >/dev/null
aws s3 cp lame.min.js "s3://$BUCKET/lame.min.js" --content-type "text/javascript; charset=utf-8" --profile "$PROFILE" >/dev/null

echo "Invalidating CloudFront cache ..."
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*" --profile "$PROFILE" >/dev/null

echo "Done. Live at https://$DIST_DOMAIN (allow ~1 minute for the cache to refresh)."
