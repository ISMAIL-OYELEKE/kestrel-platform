#!/usr/bin/env bash
# Builds the scorer Lambda package: our code plus psycopg compiled for Lambda (Linux x86_64, Python 3.13).
# boto3 is not included: the Lambda Python runtime already provides it.
# Output: app/dist/scorer.zip   Run from anywhere: app/build-lambda.sh
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build dist
mkdir -p build dist

# --platform and --only-binary download ready made Linux wheels, so this works on any machine.
python3 -m pip install --quiet --target build \
  --platform manylinux2014_x86_64 --implementation cp --python-version 3.13 --only-binary=:all: \
  "psycopg[binary]==3.3.6"

cp -r src/kestrel build/
find build -name '__pycache__' -type d -prune -exec rm -rf {} +

# Fixed timestamps, permissions and file order make the zip byte for byte identical for the same
# code, so Terraform (and the pipeline's plan) only sees a change when the code really changes.
python3 - <<'PY'
import os, zipfile
with zipfile.ZipFile("dist/scorer.zip", "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk("build"):
        dirs.sort()
        for f in sorted(files):
            path = os.path.join(root, f)
            info = zipfile.ZipInfo(os.path.relpath(path, "build"), date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as fh:
                z.writestr(info, fh.read())
PY
rm -rf build
echo "built app/dist/scorer.zip ($(du -h dist/scorer.zip | cut -f1))"
