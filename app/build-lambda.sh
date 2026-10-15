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

python3 - <<'PY'
import os, zipfile
with zipfile.ZipFile("dist/scorer.zip", "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk("build"):
        for f in sorted(files):
            path = os.path.join(root, f)
            z.write(path, os.path.relpath(path, "build"))
PY
rm -rf build
echo "built app/dist/scorer.zip ($(du -h dist/scorer.zip | cut -f1))"
