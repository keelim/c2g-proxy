#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE_PATH="${ENV_FILE:-$PROJECT_ROOT/.env}"

if [ ! -f "$ENV_FILE_PATH" ]; then
  printf 'Missing env file: %s\n' "$ENV_FILE_PATH" >&2
  exit 1
fi

# Load only shell vars for startup decisions; do not export provider secrets to Claude.
# shellcheck disable=SC1090
. "$ENV_FILE_PATH"

HOST="${LITELLM_HOST:-127.0.0.1}"
PORT="${LITELLM_PORT:-4000}"

if ! command -v claude >/dev/null 2>&1; then
  printf 'Missing required command: claude\n' >&2
  exit 1
fi

if ! lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  printf 'Starting Gemini LiteLLM bridge on http://%s:%s\n' "$HOST" "$PORT"
  sh "$SCRIPT_DIR/start-gemini-claude-proxy.sh" >/tmp/keelim-proxy-gemini-bridge.log 2>&1 &
  sleep 3
fi

if ! lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  printf 'Bridge did not start on http://%s:%s\n' "$HOST" "$PORT" >&2
  printf 'Check /tmp/keelim-proxy-gemini-bridge.log for details\n' >&2
  exit 1
fi

cd "$PROJECT_ROOT"
exec claude "$@"
