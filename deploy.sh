#!/bin/bash

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline.sh"

# Deploy to every Claude Code config dir that points at this statusline.
# ~/.claude is the primary setup; ~/.claude2 is the OpenRouter setup
# (z-ai/glm-* models). Both get the same symlink so the repo stays the
# single source of truth.
TARGETS=("$HOME/.claude/statusline.sh" "$HOME/.claude2/statusline.sh")

for TARGET in "${TARGETS[@]}"; do
    [ -d "$(dirname "$TARGET")" ] || continue

    if [ -L "$TARGET" ] && [ "$(readlink "$TARGET")" = "$SOURCE" ]; then
        echo "ok: $TARGET -> $SOURCE"
        continue
    fi

    [ -e "$TARGET" ] || [ -L "$TARGET" ] && rm "$TARGET"
    ln -s "$SOURCE" "$TARGET"
    echo "created: $TARGET -> $SOURCE"
done
