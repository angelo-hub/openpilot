#!/usr/bin/env bash
# The only way the repair agent runs tests. openpilot's environment (apt packages, scons build) is not set
# up during the repair step, so this runs pytest only if a venv already exists; the gate runs the full suite.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if [ ! -x .venv/bin/python ]; then
  echo "openpilot's environment is not built in the repair step; the gate will build and run the full suite."
  exit 0
fi
exec .venv/bin/python -m pytest -q "$@"
