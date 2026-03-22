#!/bin/sh
set -eu

print_usage() {
  cat <<'USAGE'
Usage:
  scripts/litellm/start-gemini-claude-proxy.sh [--env-file <path>] [litellm args...]

Starts a local LiteLLM proxy that exposes Anthropic-compatible endpoints for
Claude Code while routing requests to Gemini models through Google AI Studio.

Recommended first run:
  cp .env.example .env
  uv sync
  ./scripts/litellm/start-gemini-claude-proxy.sh

Required environment:
  GEMINI_API_KEY      Google AI Studio API key LiteLLM uses upstream.
  LITELLM_MASTER_KEY  Gateway auth key Claude Code should send to LiteLLM.

Optional environment:
  ENV_FILE            Override .env path (default: ./.env when present)
  LITELLM_CONFIG      Config path (default: scripts/litellm/config.gemini-claude.example.yaml)
  LITELLM_HOST        Bind host (default: 127.0.0.1)
  LITELLM_PORT        Bind port (default: 4000)

Two-key model:
  - GEMINI_API_KEY is for LiteLLM -> Gemini.
  - LITELLM_MASTER_KEY is for Claude Code -> LiteLLM.

Claude Code user-scope example (~/.claude/settings.json):
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000"
  },
  "apiKeyHelper": "bash -lc 'printf %s \"$LITELLM_MASTER_KEY\"'"
}
USAGE
}

require_env() {
  var_name="$1"
  eval "var_value=\${$var_name:-}"
  if [ -z "$var_value" ]; then
    printf 'Missing required environment variable: %s\n\n' "$var_name" >&2
    print_usage >&2
    exit 1
  fi
}

load_env_file() {
  env_file_path="$1"

  if [ -z "$env_file_path" ]; then
    return 0
  fi

  if [ ! -f "$env_file_path" ]; then
    printf 'Env file not found: %s\n' "$env_file_path" >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  . "$env_file_path"
  set +a
}

case "${1:-}" in
  -h|--help)
    print_usage
    exit 0
    ;;
esac

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_ENV_FILE="$PROJECT_ROOT/.env"
DEFAULT_CONFIG="$PROJECT_ROOT/scripts/litellm/config.gemini-claude.example.yaml"
ACTIVE_ENV_FILE="${ENV_FILE:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      [ "$#" -gt 0 ] || {
        print_usage >&2
        exit 1
      }
      ACTIVE_ENV_FILE="$1"
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [ -z "$ACTIVE_ENV_FILE" ] && [ -f "$DEFAULT_ENV_FILE" ]; then
  ACTIVE_ENV_FILE="$DEFAULT_ENV_FILE"
fi

load_env_file "$ACTIVE_ENV_FILE"

CONFIG_PATH="${LITELLM_CONFIG:-$DEFAULT_CONFIG}"
HOST="${LITELLM_HOST:-127.0.0.1}"
PORT="${LITELLM_PORT:-4000}"

if ! command -v uv >/dev/null 2>&1; then
  printf 'Missing required command: uv\n' >&2
  printf 'Install uv, then run: uv sync\n' >&2
  exit 1
fi

require_env GEMINI_API_KEY
require_env LITELLM_MASTER_KEY

if [ ! -f "$CONFIG_PATH" ]; then
  printf 'LiteLLM config not found: %s\n' "$CONFIG_PATH" >&2
  exit 1
fi

printf 'Starting LiteLLM proxy on http://%s:%s using %s\n' "$HOST" "$PORT" "$CONFIG_PATH"
if [ -n "$ACTIVE_ENV_FILE" ]; then
  printf 'Loaded environment from %s\n' "$ACTIVE_ENV_FILE"
else
  printf 'No .env loaded; using current shell environment only\n'
fi
printf 'Claude Code user-scope endpoint: ANTHROPIC_BASE_URL=http://%s:%s\n' "$HOST" "$PORT"
printf 'Claude Code auth token source: LITELLM_MASTER_KEY (set as ANTHROPIC_AUTH_TOKEN or apiKeyHelper)\n'

if [ -n "$ACTIVE_ENV_FILE" ]; then
  exec env UV_NO_ENV_FILE=1 uv run --project "$PROJECT_ROOT" --env-file "$ACTIVE_ENV_FILE" --frozen litellm --config "$CONFIG_PATH" --host "$HOST" --port "$PORT" "$@"
fi

exec env UV_NO_ENV_FILE=1 uv run --project "$PROJECT_ROOT" --frozen litellm --config "$CONFIG_PATH" --host "$HOST" --port "$PORT" "$@"
