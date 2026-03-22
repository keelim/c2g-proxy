# Claude Code via LiteLLM with a Google AI Studio Gemini key

`keelim-proxy` keeps the LiteLLM + Claude Code bootstrap close to the runtime
surface that launches the bridge. The directory is a small uv-managed project
so the onboarding flow works from `keelim-proxy/` alone.

## What lives where

### Repo-owned, safe to commit

- `.env.example`
- `pyproject.toml`
- `uv.lock`
- `scripts/litellm/config.gemini-claude.example.yaml`
- `scripts/litellm/start-gemini-claude-proxy.sh`
- `scripts/litellm/verify-gemini-claude-bridge.sh`
- this guide

### User-owned, never commit

- the populated `.env`
- `GEMINI_API_KEY`
- `LITELLM_MASTER_KEY` or a narrower LiteLLM virtual key
- `~/.claude/settings.json`
- any shell startup file or secret-manager helper that returns the LiteLLM auth
  key

## The two-key model

The setup uses two different credentials on purpose:

1. `GEMINI_API_KEY`
   - consumed by LiteLLM
   - used upstream when LiteLLM calls Gemini
2. `LITELLM_MASTER_KEY` or a LiteLLM virtual key
   - consumed by Claude Code
   - sent to LiteLLM as `ANTHROPIC_AUTH_TOKEN`

If Claude Code gets a 401 from LiteLLM, check the LiteLLM key path. If LiteLLM
reaches Gemini but gets an upstream auth or quota error, check
`GEMINI_API_KEY`.

## First-run project setup

```bash
cd keelim-proxy
cp .env.example .env
# edit .env and set real GEMINI_API_KEY / LITELLM_MASTER_KEY values
uv sync
```

The committed `.env.example` is for the local bridge runtime only. Keep Claude
Code's durable gateway auth in user scope.

## Start LiteLLM

```bash
./scripts/litellm/start-gemini-claude-proxy.sh
```

Expected defaults:

- host: `127.0.0.1`
- port: `4000`
- model aliases include `gemini-2.5-flash` and `gemini-2.5-pro`

If you keep a different env file, point the launcher at it with:

```bash
ENV_FILE=/path/to/bridge.env ./scripts/litellm/start-gemini-claude-proxy.sh
```

## Verify the gateway before launching Claude Code

```bash
./scripts/litellm/verify-gemini-claude-bridge.sh
./scripts/litellm/verify-gemini-claude-bridge.sh --live
```

Expected result with real keys:

- HTTP 200
- Anthropic-format JSON response
- text output confirming the Gemini-backed model was reached

If this request fails, fix LiteLLM first. Do not debug Claude Code until the
gateway works directly.

## Point Claude Code at LiteLLM

### Quickstart: shell env

```bash
set -a; . ./.env; set +a
export ANTHROPIC_BASE_URL="http://${LITELLM_HOST:-127.0.0.1}:${LITELLM_PORT:-4000}"
export ANTHROPIC_AUTH_TOKEN="$LITELLM_MASTER_KEY"
claude --model "${CLAUDE_BRIDGE_MODEL:-gemini-2.5-flash}"
```

### Durable user-scope setup: `~/.claude/settings.json`

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000"
  },
  "apiKeyHelper": "bash -lc 'printf %s \"$LITELLM_MASTER_KEY\"'"
}
```

## Recommended verification order

1. `cd keelim-proxy`
2. `cp .env.example .env`
3. edit `.env`
4. `uv sync`
5. start `./scripts/litellm/start-gemini-claude-proxy.sh`
6. verify `./scripts/litellm/verify-gemini-claude-bridge.sh --live`
7. run `claude --model gemini-2.5-flash`
8. optionally run `claude --model gemini-2.5-pro`
