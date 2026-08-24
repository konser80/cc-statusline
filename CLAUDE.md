# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains bash scripts for generating custom status lines with colored, formatted output:

- **statusline.sh** - Custom status line formatter for Claude Code CLI (self-contained, no network calls)
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
  - Session cost (hidden for subscription/OAuth users, shown for API token users)
  - Usage limits, read from stdin (`5h:20% (3h52m) | 7d:36% (4d0h)`)
- **Color scheme**: ANSI 256-colour indices, Tokyo Night Storm-ish. In use: 240 dark gray (separators, parent path, low usage), 8 gray (labels), 4 blue (current dir), 2 green (clean git, low context), 220 yellow (warning), 203 red (dirty git, high usage). `C_DARK_CYAN` (30), `C_CYAN` (81) and `C_LIGHT_GREEN` (78) are defined but currently unused.
- **Subscription detection**: Checks OAuth token prefix (`sk-ant-oat*`) to determine subscription vs API tokens
- **Dependencies**: jq, git, `security` (keychain, for subscription detection only)

### Usage limits block
- **Source**: `.rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` from the stdin JSON — no API call, no cache, no token needed. `resets_at` is a unix timestamp; time left is `resets_at - $(date +%s)`.
- **Output**: `5h:20% (3h52m) | 7d:36% (4d0h)` with ANSI colors
- **Color thresholds**: Each block colored by utilization:
  - ≤70%: dark gray — 70–90%: yellow — >90%: red
- **Fallbacks**: `.rate_limits` absent → block omitted entirely. Present but both percentages null → `∞` (Max subscription, no limits).

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
- statusline.sh is self-contained — everything it prints comes from the stdin JSON, except the keychain lookup used to tell subscription from API tokens.
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
