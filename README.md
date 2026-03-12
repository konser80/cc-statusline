# cc-statusline

Custom status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI.

Shows directory, git branch, context window usage with progress bar, model name, session cost, and API usage limits — all in a compact colored format.

## Requirements

- macOS
- Claude Code with OAuth token (for API usage display)

## Install

```bash
brew install jq
git clone https://github.com/konser80/cc-statusline.git
cd cc-statusline
./deploy.sh
```

This creates symlinks in `~/.claude/` pointing to the repo, so any future `git pull` updates take effect immediately.

Then add to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "statusLine": "~/.claude/statusline.sh"
}
```

## Update

```bash
cd cc-statusline
git pull
```
