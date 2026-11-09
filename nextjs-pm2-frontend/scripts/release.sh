#!/bin/bash
# Builds the Next.js app ONCE and uploads it, so every server runs the exact
# same build. Run it from your Next.js project folder, on Linux x64 (CI, WSL or
# a Linux machine), with the same Node.js major version as the servers:
#
#   /path/to/release.sh <version> <bucket>
#   /path/to/release.sh v1.4.2 "$(terraform output -raw frontend_bucket_name)"
#
# Needs output: "standalone" in next.config, and AWS credentials of someone in
# the deployer group. Then deploy it to each server: sudo deploy-frontend v1.4.2
set -euo pipefail

VERSION=${1:?usage: release.sh <version> <bucket>}
BUCKET=${2:?usage: release.sh <version> <bucket>}
[[ $VERSION =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid version: $VERSION" >&2; exit 1; }
[[ $VERSION != CURRENT ]] || { echo "CURRENT is reserved" >&2; exit 1; }
[[ -f package.json ]] || { echo "run this from the Next.js project folder" >&2; exit 1; }

# Native modules (e.g. sharp for next/image) are compiled for the build machine.
if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
  echo "build on Linux x86_64 (the servers' platform), not $(uname -s) $(uname -m)" >&2
  exit 1
fi

# A version is uploaded once; changing it later would mean servers disagree.
if aws s3api head-object --bucket "$BUCKET" --key "releases/$VERSION.tar.gz" >/dev/null 2>&1; then
  echo "releases/$VERSION.tar.gz already exists; pick a new version" >&2
  exit 1
fi

echo "Building $VERSION"
npm ci
npm run build # NEXT_PUBLIC_* variables are baked in here
[[ -f .next/standalone/server.js ]] || { echo "add output: \"standalone\" to next.config" >&2; exit 1; }

# 1. Static files first, so they exist before any server serves HTML that uses
#    them. Never --delete: visitors with older HTML still need older chunks.
echo "Uploading .next/static to s3://$BUCKET/_next/static/"
aws s3 sync .next/static "s3://$BUCKET/_next/static" \
  --cache-control "public, max-age=31536000, immutable" --only-show-errors

# 2. The server bundle: standalone server + public/ + a copy of the static files
#    (so a server can still answer /_next/static itself if asked directly).
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -a .next/standalone/. "$STAGE/"
mkdir -p "$STAGE/.next"
cp -a .next/static "$STAGE/.next/static"
[[ -d public ]] && cp -a public "$STAGE/public"
tar -czf "$STAGE.tar.gz" -C "$STAGE" .
echo "Uploading s3://$BUCKET/releases/$VERSION.tar.gz ($(du -h "$STAGE.tar.gz" | cut -f1))"
aws s3 cp "$STAGE.tar.gz" "s3://$BUCKET/releases/$VERSION.tar.gz" --only-show-errors
rm -f "$STAGE.tar.gz"

echo "Released $VERSION. On each server, one at a time: sudo deploy-frontend $VERSION"
