#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT_DIR/build/MonkeyFlash.app"

if [[ ! -d "$APP_PATH" ]]; then
  "$ROOT_DIR/build.sh"
fi

open "$APP_PATH"
