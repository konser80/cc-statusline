# cc-statusline

Custom status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI.

Shows directory, git branch, context window usage with a progress bar, model name, session cost and your 5-hour / 7-day usage limits, plus the separate weekly Fable limit once you have used any of it — in one compact colored line:

```
 konser/js/statusline | git:main ✓ | opus 5 45% ▓▓▓▓░░░░░░ 67k/1M | 5h:9% (11m) | 7d:4% (5d22h) | fable:2% (1d15h)
```

Everything except the token-type check and the Fable limit comes from the JSON that Claude Code feeds the script on stdin. That JSON has no per-model limits, so for subscription users the Fable percentage is fetched from `https://api.anthropic.com/api/oauth/usage` with the OAuth token from the keychain, cached in `~/.cache/statusline-fable` and refreshed in the background at most every 2 minutes.

## Requirements

- **Claude Code 2.1.80 or newer.** The `rate_limits` field arrived in 2.1.80; on older versions the `5h` / `7d` block is silently omitted and the rest still works.
- `jq` and `git`
- macOS, or Linux with one caveat — see below

## Install

```bash
brew install jq
git clone https://github.com/konser80/cc-statusline.git
cd cc-statusline
./deploy.sh
```

`deploy.sh` symlinks `~/.claude/statusline.sh` to the script in the clone, so later updates take effect without re-running it.

Then point Claude Code at it in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/bin/bash ~/.claude/statusline.sh",
    "padding": 0
  }
}
```

## Update

```bash
cd cc-statusline
git pull
```

That is the whole update. `git clone` recorded where to pull from, and the symlink means the new version is live immediately — no need to run `deploy.sh` again.

Forgot where you cloned it? `readlink ~/.claude/statusline.sh` prints the path.

## Linux

The script itself is portable. The one macOS-specific call is `security`, used only to read the token prefix and decide whether to display session cost: `sk-ant-oat*` means a Pro/Max subscription, where the cost figure is meaningless, so it is hidden.

On Linux that call fails silently: session cost is always shown and the Fable block never appears, since it needs the OAuth token. Everything else — path, git, context window, 5h / 7d limits — works unchanged.

Usage blocks turn yellow above 70% and red above 90%.

## Debugging

```bash
./test-statusline.sh    # render the line from sample data
```

To capture what Claude Code actually sends, export `STATUSLINE_DEBUG=1` in the shell you start Claude Code from. Each render then writes its stdin JSON to `~/.cache/statusline-input.json` (mode 0600 — it contains `session_id`, `cwd` and `transcript_path`). Replay it with:

```bash
bash statusline.sh < ~/.cache/statusline-input.json
```
