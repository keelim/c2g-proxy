# keelim-proxy

This directory hosts the LiteLLM + Claude Code + Gemini bridge bootstrap as a
small uv-managed project.

## Files

- `.env.example`
- `.gitignore`
- `pyproject.toml`
- `uv.lock`
- `scripts/litellm/config.gemini-claude.example.yaml`
- `scripts/litellm/start-gemini-claude-proxy.sh`
- `scripts/litellm/verify-gemini-claude-bridge.sh`
- `scripts/litellm/print-litellm-master-key.sh`
- `scripts/litellm/open-claude-gemini.sh`
- `docs/claude-code-via-litellm-gemini.md`
- `docs/claude-code-via-litellm-gemini-verification.md`

## Two-key model

- `GEMINI_API_KEY` -> LiteLLM uses this upstream with Gemini.
- `LITELLM_MASTER_KEY` (or a narrower LiteLLM virtual key) -> Claude Code sends
  this to LiteLLM as `ANTHROPIC_AUTH_TOKEN`.

Do **not** paste the Gemini provider key into Claude Code's Anthropic auth
setting.

## Quickstart

```bash
cd keelim-proxy
cp .env.example .env
# edit .env with real values
uv sync
./scripts/litellm/start-gemini-claude-proxy.sh
./scripts/litellm/verify-gemini-claude-bridge.sh
./scripts/litellm/verify-gemini-claude-bridge.sh --live
export ANTHROPIC_AUTH_TOKEN="$LITELLM_MASTER_KEY"
claude --model gemini-2.5-flash
```

## Persistent Claude usage

If `~/.claude/settings.json` points at the local bridge, you can open Claude
through the helper below and it will start the bridge on demand:

```bash
./scripts/litellm/open-claude-gemini.sh
./scripts/litellm/open-claude-gemini.sh -p "Reply with exactly OK"
```

## Scope boundary

The project `.env` is only for the local LiteLLM bridge runtime. Keep Claude
Code gateway settings in `~/.claude/settings.json` or another user-scoped secret
source.
