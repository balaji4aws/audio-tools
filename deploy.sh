#!/usr/bin/env bash
# Redeploy Audio Clip & Combine: upload the static files and refresh CloudFront.
# Reads bucket/distribution info from .deploy-info (created at first deploy).
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .deploy-info ]; then
  cat >&2 <<'EOF'
Missing .deploy-info — can't find the target bucket/distribution.
Create it next to this script with your own values:

  BUCKET=my-bucket-name
  DIST_ID=E1234567890ABC
  DIST_DOMAIN=dxxxxxxxxxxxx.cloudfront.net
  PROFILE=my-aws-profile
EOF
  exit 1
fi
# shellcheck disable=SC1091
source .deploy-info

# Fail early with a clear message rather than handing the AWS CLI an empty
# bucket name / distribution id.
for v in BUCKET DIST_ID DIST_DOMAIN PROFILE; do
  if [ -z "${!v:-}" ]; then
    echo "Missing $v in .deploy-info." >&2
    exit 1
  fi
done

command -v aws >/dev/null 2>&1 || {
  echo "Error: the AWS CLI is not installed or not on PATH. See https://aws.amazon.com/cli/" >&2
  exit 1
}

echo "Uploading files to s3://$BUCKET ..."
aws s3 cp index.html  "s3://$BUCKET/index.html"  --content-type "text/html; charset=utf-8"       --profile "$PROFILE" >/dev/null
aws s3 cp lame.min.js "s3://$BUCKET/lame.min.js" --content-type "text/javascript; charset=utf-8" --profile "$PROFILE" >/dev/null

echo "Invalidating CloudFront cache ..."
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*" --profile "$PROFILE" >/dev/null

echo "Done. Live at https://$DIST_DOMAIN (allow ~1 minute for the cache to refresh)."
