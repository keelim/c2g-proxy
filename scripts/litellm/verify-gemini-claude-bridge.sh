#!/bin/sh
set -eu

print_usage() {
  cat <<'USAGE'
Usage:
  scripts/litellm/verify-gemini-claude-bridge.sh [--live] [--model <name>] [--base-url <url>] [--env-file <path>] [--settings <path>]

Checks the safe Claude Code <-> LiteLLM <-> Gemini bridge assumptions.

Default mode:
  - local-only/static checks

--live:
  - also POSTs a small request to /v1/messages using the gateway token
    from ANTHROPIC_AUTH_TOKEN or LITELLM_MASTER_KEY

Options:
  --model <name>     LiteLLM model alias to probe (default: $CLAUDE_BRIDGE_MODEL or gemini-2.5-flash)
  --base-url <url>   Anthropic-format LiteLLM base URL (default: $ANTHROPIC_BASE_URL or http://127.0.0.1:4000)
  --env-file <path>  Override .env path (default: ./.env when present)
  --settings <path>  Claude Code user settings path (default: $CLAUDE_SETTINGS_PATH or ~/.claude/settings.json)
  -h, --help         Show help
USAGE
}

pass() {
  printf 'PASS  %s\n' "$1"
}

warn() {
  printf 'WARN  %s\n' "$1"
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  printf 'FAIL  %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

load_env_file() {
  env_file_path="$1"

  if [ -z "$env_file_path" ]; then
    return 0
  fi

  if [ ! -f "$env_file_path" ]; then
    fail "env file not found: $env_file_path"
    return 1
  fi

  set -a
  # shellcheck disable=SC1090
  . "$env_file_path"
  set +a
  return 0
}

run_project_python() {
  if ! command -v uv >/dev/null 2>&1; then
    printf 'uv is required for project-local verification\n' >&2
    return 127
  fi

  if [ -n "$ACTIVE_ENV_FILE" ]; then
    UV_NO_ENV_FILE=1 uv run --project "$PROJECT_ROOT" --env-file "$ACTIVE_ENV_FILE" --frozen python "$@"
    return 0
  fi

  UV_NO_ENV_FILE=1 uv run --project "$PROJECT_ROOT" --frozen python "$@"
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_ENV_FILE="$PROJECT_ROOT/.env"
ACTIVE_ENV_FILE="${ENV_FILE:-}"
LIVE_MODE="0"
MODEL="${CLAUDE_BRIDGE_MODEL:-gemini-2.5-flash}"
BASE_URL="${ANTHROPIC_BASE_URL:-http://127.0.0.1:4000}"
SETTINGS_PATH="${CLAUDE_SETTINGS_PATH:-$HOME/.claude/settings.json}"
FAILURES=0
WARNINGS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --live)
      LIVE_MODE="1"
      ;;
    --model)
      shift
      [ "$#" -gt 0 ] || {
        print_usage
        exit 1
      }
      MODEL="$1"
      ;;
    --base-url)
      shift
      [ "$#" -gt 0 ] || {
        print_usage
        exit 1
      }
      BASE_URL="$1"
      ;;
    --env-file)
      shift
      [ "$#" -gt 0 ] || {
        print_usage
        exit 1
      }
      ACTIVE_ENV_FILE="$1"
      ;;
    --settings)
      shift
      [ "$#" -gt 0 ] || {
        print_usage
        exit 1
      }
      SETTINGS_PATH="$1"
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      print_usage
      exit 1
      ;;
  esac
  shift
done

if [ -z "$ACTIVE_ENV_FILE" ] && [ -f "$DEFAULT_ENV_FILE" ]; then
  ACTIVE_ENV_FILE="$DEFAULT_ENV_FILE"
fi

if ! load_env_file "$ACTIVE_ENV_FILE"; then
  exit 1
fi

GATEWAY_TOKEN="${ANTHROPIC_AUTH_TOKEN:-${LITELLM_MASTER_KEY:-}}"

printf 'Base URL: %s\n' "$BASE_URL"
printf 'Model: %s\n' "$MODEL"
printf 'Mode: %s\n' "$( [ "$LIVE_MODE" = "1" ] && printf 'live' || printf 'static' )"
if [ -n "$ACTIVE_ENV_FILE" ]; then
  printf 'Env file: %s\n' "$ACTIVE_ENV_FILE"
else
  printf 'Env file: (none)\n'
fi
printf '\n'

if [ -f "$PROJECT_ROOT/.env.example" ]; then
  pass "project .env.example is present for local onboarding"
else
  fail "missing project .env.example"
fi

case "$BASE_URL" in
  http://127.0.0.1:*|http://localhost:*|https://127.0.0.1:*|https://localhost:*)
    pass "base URL points at a local LiteLLM endpoint"
    ;;
  *)
    fail "base URL should normally point at localhost/127.0.0.1 for this setup"
    ;;
esac

if ! command -v uv >/dev/null 2>&1; then
  fail "uv is required for JSON validation; install uv first"
fi

if [ -f "$SETTINGS_PATH" ]; then
  if run_project_python - "$SETTINGS_PATH" "$BASE_URL" <<'PY'
import json
import sys

settings_path = sys.argv[1]
expected_base_url = sys.argv[2]

with open(settings_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

env_block = data.get("env", {}) or {}
if not isinstance(env_block, dict):
    raise SystemExit("env block is not an object")

if "GEMINI_API_KEY" in env_block:
    raise SystemExit("GEMINI_API_KEY must not be stored in ~/.claude/settings.json")

anthropic_base = env_block.get("ANTHROPIC_BASE_URL")
api_key_helper = data.get("apiKeyHelper")
anthropic_token = env_block.get("ANTHROPIC_AUTH_TOKEN")

if not anthropic_base and not api_key_helper and not anthropic_token:
    raise SystemExit("settings file is missing ANTHROPIC_BASE_URL and auth configuration")

if anthropic_base and anthropic_base != expected_base_url:
    raise SystemExit(
        f"settings ANTHROPIC_BASE_URL mismatch: {anthropic_base} != {expected_base_url}"
    )
PY
  then
    pass "settings file keeps Gemini auth out of Claude settings and exposes Claude-side auth/base URL"
  else
    fail "settings file review"
  fi
else
  warn "settings file not found at $SETTINGS_PATH (shell env may still be valid)"
fi

if [ -n "${GEMINI_API_KEY:-}" ] && [ -n "$GATEWAY_TOKEN" ]; then
  if [ "$GEMINI_API_KEY" = "$GATEWAY_TOKEN" ]; then
    fail "GEMINI_API_KEY and gateway token must not be the same value"
  else
    pass "provider and gateway tokens are distinct"
  fi
else
  warn "current env does not expose both GEMINI_API_KEY and a gateway token for comparison"
fi

if [ "$LIVE_MODE" = "1" ]; then
  if [ -z "$GATEWAY_TOKEN" ]; then
    fail "--live requires ANTHROPIC_AUTH_TOKEN or LITELLM_MASTER_KEY"
  else
    response_file="$(mktemp)"
    http_code="$({
      curl -sS -o "$response_file" -w '%{http_code}' \
        "$BASE_URL/v1/messages" \
        -H "Authorization: Bearer $GATEWAY_TOKEN" \
        -H 'Content-Type: application/json' \
        -d "{
          \"model\": \"$MODEL\",
          \"max_tokens\": 32,
          \"messages\": [{\"role\": \"user\", \"content\": \"Reply with OK\"}]
        }"
    } || printf '000')"

    if [ "$http_code" = "200" ]; then
      if run_project_python - "$response_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

content = data.get("content")
if not isinstance(content, list) or not content:
    raise SystemExit("missing Anthropic-style content array")
PY
      then
        pass "live /v1/messages smoke test returned Anthropic-style content"
      else
        fail "live /v1/messages response shape"
      fi
    else
      fail "live /v1/messages smoke test returned HTTP $http_code"
      printf '%s\n' '--- response excerpt ---'
      sed -n '1,40p' "$response_file"
    fi

    rm -f "$response_file"
  fi
fi

printf '\nSummary: %s failure(s), %s warning(s)\n' "$FAILURES" "$WARNINGS"

if [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
