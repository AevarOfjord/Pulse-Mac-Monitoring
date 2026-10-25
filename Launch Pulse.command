#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -d build/Pulse.app ]]; then
    open build/Pulse.app
else
    ./scripts/build-app.sh --open
fi
