# cc-statusline

Custom status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI, one compact colored line:

```
 konser/js/statusline | git:main ✓ | opus 5.5·m 45% ▓▓▓▓░░░░░░ 450k/1M ❄8m | 5h:9% (11m) | 7d:4% (5d22h) | fable:2%
```

| Block | Meaning |
|---|---|
| `konser/js/statusline` | Last 3 components of the working directory |
| `git:main ✓` | Branch, `✓` clean / `✗` dirty. `⇡` — branch differs from its upstream or was never pushed, `⌀` — no remote configured |
| `opus 5.5·m` | Model and effort level: `l` / `m` / `h` / `x` for low / medium / high / xhigh, `max` spelled out. `⤳` in front marks a non-Anthropic model |
| `45% ▓▓▓▓░░░░░░ 450k/1M` | Context window usage |
| `❄8m` | Minutes until the prompt cache expires; a bare red `❄` once it has. After that the next request re-pays for the whole context. Shown for the last 10 minutes only, and only from 30k tokens of context |
| `$0.1234` | Session cost — API tokens and OpenRouter only, hidden for Pro/Max subscriptions |
| `5h:9% (11m)`, `7d:4% (5d22h)` | Usage limits and time until reset; `∞` when the plan has none |
| `fable:2%` | Separate weekly Fable limit, subscriptions only, once any of it is used |

Limit blocks turn yellow above 70% and red above 90%.

## Requirements

- Claude Code 2.1.80 or newer — older versions have no `rate_limits`, so the `5h` / `7d` blocks are omitted
- `jq`, `git`, `curl`
- macOS, or Linux with a caveat — see [Linux](#linux)

## Install

```bash
brew install jq
git clone https://github.com/konser80/cc-statusline.git
cd cc-statusline
./deploy.sh
```

`deploy.sh` symlinks `~/.claude/statusline.sh` to the script in the clone. Then merge this key into `~/.claude/settings.json`, keeping the rest of the file:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/bin/bash ~/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 60
  }
}
```

All four fields are part of the install — an agent setting this up must write `refreshInterval` too. Without it Claude Code redraws the line only on events, so the cache countdown and the time left in `5h` / `7d` freeze while the session is idle. The value is in seconds.

## Update

```bash
cd cc-statusline && git pull
```

The symlink makes the new version live immediately. `readlink ~/.claude/statusline.sh` prints where the clone is.

## Where the data comes from

Almost everything is read from the JSON Claude Code feeds the script on stdin. The exceptions:

- **Token type** — the OAuth token prefix from the macOS keychain tells a subscription (`sk-ant-oat*`) from an API token.
- **Cache countdown** — the last 200 lines of the session transcript. An estimate: subagent requests have their own cache and are not counted.
- **Fable limit** — `https://api.anthropic.com/api/oauth/usage` with the keychain OAuth token, refreshed in the background at most every 2 minutes, cached in `~/.cache/statusline-fable`.
- **OpenRouter cost** — see below.

## Non-Anthropic models (OpenRouter)

Any model whose id does not start with `claude-` is treated as an OpenRouter session:

```
 konser/js/statusline | git:main ✓ | ⤳ glm-5.3 13% ▓░░░░░░░░░ 26k/200k | $4.8779
```

The cost needs your OpenRouter API key in `OPENROUTER_CC_KEY`, exported in the shell profile you start Claude Code from:

```bash
export OPENROUTER_CC_KEY="sk-or-v1-..."
```

The same variable can feed Claude Code itself:

```bash
ANTHROPIC_BASE_URL="https://openrouter.ai/api" \
ANTHROPIC_AUTH_TOKEN="$OPENROUTER_CC_KEY" \
ANTHROPIC_API_KEY="" \
ANTHROPIC_DEFAULT_OPUS_MODEL="z-ai/glm-5.3" \
claude
```

Without `OPENROUTER_CC_KEY` the script falls back to `ANTHROPIC_AUTH_TOKEN`, but only when `ANTHROPIC_BASE_URL` points at openrouter.ai. No key — no cost, the rest of the line works.

The figure is what OpenRouter actually billed: the script asks `/api/v1/generation` for every response of the session in the background and sums the results in `~/.cache/statusline-openrouter-cost/`. Claude Code's own cost figure is priced against Anthropic's rate card and is wrong for these models. The total trails the session by a few seconds to a few minutes; requests outside the transcript, such as title generation, are not counted.

## Linux

The only macOS-specific call is `security` (keychain). On Linux it fails silently, so the token is treated as an API token: session cost is always shown and the Fable block never appears. Everything else works unchanged.

## Debugging

```bash
./test-statusline.sh    # render the line from sample data
```

To capture what Claude Code actually sends, export `STATUSLINE_DEBUG=1` in the shell you start it from. Each render then writes its stdin JSON to `~/.cache/statusline-input-<session_id>.json` (mode 0600), which you can replay:

```bash
bash statusline.sh < ~/.cache/statusline-input-<session_id>.json
```
