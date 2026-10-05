# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains bash scripts for generating custom status lines with colored, formatted output:

- **statusline.sh** - Custom status line formatter for Claude Code CLI (one cached background API call, for the Fable limit only)
- **debug-claude-api.sh** - Standalone debug tool to test API requests and response. Not used by statusline.sh, and gitignored via `debug-*` — it exists only in a working copy, not in a fresh clone.
- **deploy.sh** - Deploys a symlink from this repo to `~/.claude/`
- **test-statusline.sh** - Test script with sample JSON data

## Deployment

```bash
./deploy.sh  # Creates ~/.claude/statusline.sh symlink → this repo
```

Claude Code runs `~/.claude/statusline.sh` (symlink → this repo), so edits in the repo take effect immediately.

## Testing Scripts

```bash
./test-statusline.sh           # Full statusline with all components
./debug-claude-api.sh          # Debug API request/response (standalone, may be absent)
```

## Key Architecture

### statusline.sh
- **Input**: Reads JSON from stdin (provided by Claude Code)
- **Output**: Formatted status line with:
  - Shortened directory path (last 3 components)
  - Git branch and clean/dirty status
  - Context window usage with progress bar (raw `.context_window.used_percentage`)
  - Model name
  - Session cost — three cases: OpenRouter models (non-`claude-*` id) show what OpenRouter actually billed for the session's responses; Anthropic API tokens show Claude Code's `cost.total_cost_usd`; subscription/OAuth users get no cost
  - Usage limits, read from stdin (`5h:20% (3h52m) | 7d:36% (4d0h)`)
- **Color scheme**: ANSI 256-colour indices, Tokyo Night Storm-ish. In use: 240 dark gray (separators, parent path, low usage), 8 gray (labels), 4 blue (current dir), 2 green (clean git, low context), 220 yellow (warning), 203 red (dirty git, high usage). `C_DARK_CYAN` (30), `C_CYAN` (81) and `C_LIGHT_GREEN` (78) are defined but currently unused.
- **Subscription detection**: Checks OAuth token prefix (`sk-ant-oat*`) to determine subscription vs API tokens. Non-Anthropic models (OpenRouter, `model.id` not `claude-*`) are detected separately and marked with a `⤳` icon before the model name.
- **Dependencies**: jq, git, `security` (keychain, for subscription detection only), `awk`, `curl` and `OPENROUTER_CC_KEY` (OpenRouter session cost)

### Usage limits block
- **Source**: `.rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` from the stdin JSON — no API call, no cache, no token needed. `resets_at` is a unix timestamp; time left is `resets_at - $(date +%s)`.
- **Output**: `5h:20% (3h52m) | 7d:36% (4d0h)` with ANSI colors
- **Color thresholds**: Each block colored by utilization:
  - ≤70%: dark gray — 70–90%: yellow — >90%: red
- **Fallbacks**: `.rate_limits` absent → block omitted entirely. Present but both percentages null → `∞` (Max subscription, no limits).

### Fable limit block (network call)
- **Why the API**: stdin `rate_limits` has only `five_hour`/`seven_day`; the per-model weekly Fable window exists only in the usage API's `limits[]` (`kind: "weekly_scoped"`, `scope.model.display_name: "Fable"`, integer `percent`, ISO `resets_at`).
- **Output**: third block after `7d:`, same format — `fable:2% (1d15h)`. Shown only for OAuth tokens, only when `percent` > 0.
- **Cache**: `~/.cache/statusline-fable` holds `"<percent> <resets_at epoch>"`, or an empty line when the account has no Fable row. Older than 2 min → refresh in a background subshell (mkdir lock `statusline-fable.lock`, stale after 1 min); the render always uses whatever is cached, so the first render after a cold start shows no Fable block.
- **Safety**: `curl --fail --max-time 5`; the cache is only written when the response has a `limits` array (an error body must not poison it), via temp file + `mv`.

### OpenRouter cost block (network call, only for non-Anthropic models)
- **Why the API**: neither local figure matches the bill. Claude Code's `cost.total_cost_usd` is priced against its own Anthropic rate card, and tokens × the public `/api/v1/models` prices is off too — for one `z-ai/glm-5.2` session Claude Code said $11.11, catalog prices gave $0.76, OpenRouter billed $4.88. Don't go back to either. For models whose `id` does not start with `claude-`, the cost is the sum of `total_cost` from `GET https://openrouter.ai/api/v1/generation?id=<gen-…>` over every response id found in `transcript_path` and in `<transcript minus .jsonl>/subagents/*.jsonl`.
- **Key**: `OPENROUTER_CC_KEY`; falls back to `ANTHROPIC_AUTH_TOKEN` only when `ANTHROPIC_BASE_URL` points at openrouter.ai. No key → no cost shown. The key reaches curl through a config on stdin (`-K -`), never argv.
- **Output**: `$4.8779`, same slot/format as the Anthropic cost. Per session — two concurrent sessions each show their own total. Requests that never reach the transcript (e.g. title generation) are not counted.
- **Cache**: `~/.cache/statusline-openrouter-cost/<session_id>` holds one `"<gen_id> <cost>"` line per response. A render sums it as is; when a transcript is newer than the cache, a background subshell fetches the missing ids (50 per pass, sequential, one retry after 3 s; lock `<cache>.lock`, stale after 3 min). The cache's mtime is the "up to date" marker: set to the pass's start time when nothing is pending, aged to year 2000 when work is left so the next render continues. So the figure trails the last response by one render, and a resumed long session catches up over a few renders.
- **Safety**: `curl --fail --max-time 5` per request; only responses with a `total_cost` are recorded, via temp file + `mv`. Ids still unknown an hour after they were issued (OpenRouter can take minutes to expose a generation) (timestamp is inside the id) are recorded as `0` so they aren't retried forever.

### debug-claude-api.sh
- **Purpose**: Debug tool to test API connection and view raw responses
- **Output**: Shows keychain access, token extraction, HTTP status, and formatted JSON

### deploy.sh
- **Purpose**: Create a symlink in `~/.claude/` pointing to statusline.sh in this repo

### debug-claude-api.sh only (statusline.sh does none of this)
- **Authentication**: OAuth token from macOS keychain (`Claude Code-credentials`)
- **API endpoint**: `https://api.anthropic.com/api/oauth/usage`
- **API header**: `anthropic-beta: oauth-2025-04-20`

## Important Details

**Script conventions:**
- Everything statusline.sh prints comes from the stdin JSON, except the keychain lookup used to tell subscription from API tokens and the Fable limit (usage API, see above). Don't move 5h/7d back to the API — stdin has them.
- Important: Don't use `printf` with captured output containing `%` symbols - use direct string concatenation

**Context window display in statusline.sh:**
- The bar shows `.context_window.used_percentage` from Claude Code, unmodified — plain share of the full context window.
- Do NOT reintroduce a "percentage until autocompact" recalculation. It used to assume a fixed 83.5% threshold; the autocompact threshold is user-configurable now, so no hardcoded constant can be right.
- Token counts next to the bar are the sum of `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.

**Token types:**
- `sk-ant-oat*` — OAuth token (subscription Pro/Max), no cost display
- `sk-ant-api*` — API token (pay-per-use), shows session cost

**Platform notes:**
- statusline.sh no longer uses `stat -f` or `date -j` — the date parsing that required them went away with the API layer. The remaining `security` call is macOS-only, but only gates cost display.
