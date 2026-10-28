# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

- **statusline.sh** - Custom status line for Claude Code CLI. Claude Code runs `~/.claude/statusline.sh`, a symlink to this repo (`./deploy.sh` creates it), so edits take effect immediately.
- **test-statusline.sh** - Renders the status line from sample JSON: `./test-statusline.sh`
- **debug-claude-api.sh** - Standalone tool that calls `https://api.anthropic.com/api/oauth/usage` with the keychain OAuth token and prints the raw response. Not used by statusline.sh; gitignored via `debug-*`, so it may be absent.

Dependencies: jq, git, awk, curl, `security` (macOS keychain, only to tell subscription from API tokens).

## Status line contents

Everything comes from the stdin JSON, except: the keychain lookup, the Fable limit (usage API), the OpenRouter cost (OpenRouter API), the prompt cache countdown (transcript tail) and the CLAUDE.md size (`wc -c`).

- **Directory**: last 3 path components.
- **Git**: branch and clean/dirty status.
- **Context**: raw `.context_window.used_percentage` with a bar. Percentage green ≤40%, yellow 40–65%, orange 65–80%, red >80%; the bar stays dark gray up to 40%, then follows the percentage colour. 40% is low on purpose: it is already 400k tokens in a 1M window. Token count = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.
- **Cache countdown**: glued to the token count (`40k/200k ❄8m`), see below.
- **CLAUDE.md size** (`md:18k`): bytes of `<.workspace.project_dir>/CLAUDE.md` only (no `.claude/CLAUDE.md`, `CLAUDE.local.md` or `@imports`), KB rounded down. Hidden below 15 KB, dark gray from 15, yellow from 25, red from 40.
- **Model** with effort glued on (`opus 5.5·m`): `.effort.level` as `l`/`m`/`h`/`x`, `max` spelled out, no suffix when absent. Non-`claude-*` models (OpenRouter) get a `⤳` icon.
- **Cost**: OpenRouter models show what OpenRouter billed (see below); API tokens (`sk-ant-api*`) show `cost.total_cost_usd`; OAuth/subscription tokens (`sk-ant-oat*`) show nothing.
- **Usage limits**: `5h:20% (3h52m) | 7d:36% (4d) | fable:2%` from `.rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`. Dark gray ≤80%, yellow 80–90%, red >90%. `.rate_limits` absent → no block; both percentages null → `∞`.

**Colours**: defined at the top of statusline.sh. Green, yellow, orange and red are truecolor when `$COLORTERM` is `truecolor`/`24bit`, with a 256-colour fallback; the rest are 256-colour indices. Dark gray (240) is for things that shouldn't draw the eye, yellow/orange/red for warnings.

## Rules

- Don't move 5h/7d back to the API — stdin has them.
- The context bar shows `used_percentage` unmodified. Do NOT reintroduce a "percentage until autocompact" recalculation: the autocompact threshold is user-configurable, so no hardcoded constant can be right.
- Don't use `printf` with captured output containing `%` — use string concatenation.
- Network calls never block a render: they run in a background subshell behind a mkdir lock, the render uses whatever is cached, curl has `--fail --max-time 5`, and caches are written via temp file + `mv` only from a valid response.

## Prompt cache countdown

- **Why**: the API keeps the processed context for 5 min or 1 h after the last request; after that the next request re-pays for the whole context.
- **Source**: last 200 lines of `transcript_path` (stdin has neither the time nor the TTL). Time = `timestamp` of the last main-chain `assistant` entry that touched the cache; TTL from the last write in the tail (`ephemeral_5m_input_tokens` > 0 → 5 min, `ephemeral_1h_input_tokens` → 1 h; no write → 1 h for OAuth, 5 min otherwise).
- **Output**: `❄8m` when `CACHE_SHOW_SECS` (600) or less is left, yellow for the last sixth of the window; bare red `❄` once expired. So a 1-hour cache is hidden for the first 50 min, a 5-minute one is always shown. Hidden for non-`claude-*` models and below `CACHE_MIN_TOKENS` (30k).
- It is an estimate: the API counts from the start of a request, the transcript records its end.
- Needs `statusLine.refreshInterval` (60 in `~/.claude/settings.json`), otherwise the countdown freezes while idle.

## Fable limit (usage API)

- **Why the API**: stdin `rate_limits` has only `five_hour`/`seven_day`; the weekly Fable window is only in the usage API's `limits[]` (`kind: "weekly_scoped"`, `scope.model.display_name: "Fable"`).
- Shown only for OAuth tokens and only when `percent` > 0, percentage only.
- Cache `~/.cache/statusline-fable` (`"<percent> <resets_at>"`, empty line = no Fable row), refreshed when older than 2 min. The first render after a cold start shows no Fable block.

## OpenRouter cost (non-`claude-*` models)

- **Why the API**: neither local figure matches the bill. For one `z-ai/glm-5.2` session `cost.total_cost_usd` said $11.11, tokens × `/api/v1/models` prices gave $0.76, OpenRouter billed $4.88. Don't go back to either.
- **How**: sum of `total_cost` from `GET /api/v1/generation?id=<gen-…>` over every response id in `transcript_path` and `<transcript minus .jsonl>/subagents/*.jsonl`. Per session; requests that never reach the transcript (e.g. title generation) aren't counted.
- **Key**: `OPENROUTER_CC_KEY`, or `ANTHROPIC_AUTH_TOKEN` when `ANTHROPIC_BASE_URL` points at openrouter.ai; no key → no cost. Passed to curl via `-K -`, never argv.
- **Cache**: `~/.cache/statusline-openrouter-cost/<session_id>`, one `"<gen_id> <cost>"` line per response. When a transcript is newer than the cache, a background pass fetches missing ids (`OR_BATCH` per pass). The cache's mtime is the "up to date" marker: aged to year 2000 when work is left, so the next render continues. The figure trails the last response by one render. Ids still unknown an hour after issue are recorded as `0`.
