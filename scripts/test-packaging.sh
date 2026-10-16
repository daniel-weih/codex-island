#!/bin/zsh

set -euo pipefail
ROOT_DIR="${0:A:h:h}"
python3 "$ROOT_DIR/Tests/PackagingChecks/run.py"
