# Claude Code via LiteLLM (Gemini) — verification checklist

Run these checks from the `keelim-proxy/` directory so the helper paths and uv
project resolution stay consistent.

This checklist is the verification companion for a Claude Code + LiteLLM +
Gemini setup. It is intentionally non-secret: keep `GEMINI_API_KEY`,
`LITELLM_MASTER_KEY`, and any narrower LiteLLM virtual keys in `.env`, your
shell, secret manager, or other user-scoped config only.

## First-run setup

```bash
cd keelim-proxy
cp .env.example .env
# edit .env with real keys
uv sync
```

## Two-key review gate

- `GEMINI_API_KEY` is for **LiteLLM -> Gemini**
- `LITELLM_MASTER_KEY` (or the value you export as `ANTHROPIC_AUTH_TOKEN`) is
  for **Claude Code -> LiteLLM**

## Static verification

```bash
./scripts/litellm/verify-gemini-claude-bridge.sh
```

## uv runtime verification

```bash
uv run litellm --help
```

## Live gateway verification

```bash
./scripts/litellm/verify-gemini-claude-bridge.sh --live --model gemini-2.5-flash
```

## Claude Code smoke test

```bash
set -a; . ./.env; set +a
export ANTHROPIC_BASE_URL="http://${LITELLM_HOST:-127.0.0.1}:${LITELLM_PORT:-4000}"
export ANTHROPIC_AUTH_TOKEN="$LITELLM_MASTER_KEY"
claude --model "${CLAUDE_BRIDGE_MODEL:-gemini-2.5-flash}"
```
