#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.claude"

# List of scripts to symlink
SCRIPTS=(
    "statusline.sh"
    "statusline-claude-usage.sh"
)

for script in "${SCRIPTS[@]}"; do
    SOURCE="$SCRIPT_DIR/$script"
    TARGET="$DEST_DIR/$script"

    if [ -L "$TARGET" ] && [ "$(readlink "$TARGET")" = "$SOURCE" ]; then
        echo "ok: $TARGET -> $SOURCE"
        continue
    fi

    if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
        echo "removing: $TARGET"
        rm "$TARGET"
    fi

    ln -s "$SOURCE" "$TARGET"
    echo "created: $TARGET -> $SOURCE"
done
