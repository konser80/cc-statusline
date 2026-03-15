#!/bin/bash

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline.sh"
TARGET="$HOME/.claude/statusline.sh"

if [ -L "$TARGET" ] && [ "$(readlink "$TARGET")" = "$SOURCE" ]; then
    echo "ok: $TARGET -> $SOURCE"
    exit 0
fi

[ -e "$TARGET" ] || [ -L "$TARGET" ] && rm "$TARGET"
ln -s "$SOURCE" "$TARGET"
echo "created: $TARGET -> $SOURCE"
