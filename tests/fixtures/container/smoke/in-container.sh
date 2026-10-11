#!/bin/sh
# Runs inside the fixture container (image-gate `exec`).
set -eu
test -f /www/index.html
grep -q . /www/version.txt
echo "in-container checks passed"
