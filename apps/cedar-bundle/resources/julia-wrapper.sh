#!/bin/bash
# Julia wrapper for Cedar app
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export JULIA_DEPOT_PATH="$SCRIPT_DIR/julia_env/depot"
export JULIA_PROJECT="$SCRIPT_DIR/julia_env"
exec "$SCRIPT_DIR/julia/bin/julia" "$@"
