#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE_PATH="${ENV_FILE:-$PROJECT_ROOT/.env}"

if [ ! -f "$ENV_FILE_PATH" ]; then
  printf 'Missing env file: %s\n' "$ENV_FILE_PATH" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE_PATH"
set +a

if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
  printf 'Missing LITELLM_MASTER_KEY in %s\n' "$ENV_FILE_PATH" >&2
  exit 1
fi

printf %s "$LITELLM_MASTER_KEY"
