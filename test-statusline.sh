#!/bin/bash

# Test script to demonstrate statusline.sh output with colors

echo "Testing statusline.sh with sample data..."
echo "=========================================="
echo ""

# Reset timestamps are relative to now, so the remaining-time formatting stays meaningful
RESET_5H=$(( $(date +%s) + 3600 * 3 + 52 * 60 ))
RESET_7D=$(( $(date +%s) + 86400 * 4 ))

# One response 52 min ago written to the 1-hour cache → the countdown shows ❄8m
TRANSCRIPT=$(mktemp)
trap 'rm -f "$TRANSCRIPT"' EXIT
LAST_TS=$(date -u -r $(( $(date +%s) - 52 * 60 )) +%Y-%m-%dT%H:%M:%S.000Z)
echo "{\"type\":\"assistant\",\"timestamp\":\"$LAST_TS\",\"message\":{\"usage\":{\"cache_read_input_tokens\":10000,\"cache_creation_input_tokens\":5000,\"cache_creation\":{\"ephemeral_5m_input_tokens\":0,\"ephemeral_1h_input_tokens\":5000}}}}" > "$TRANSCRIPT"

cat << EOF | "$(dirname "$0")/statusline.sh"
{
  "workspace": {
    "current_dir": "/Users/konser/js/statusline"
  },
  "context_window": {
    "current_usage": {
      "input_tokens": 25000,
      "cache_creation_input_tokens": 5000,
      "cache_read_input_tokens": 10000
    },
    "context_window_size": 200000
  },
  "model": {
    "display_name": "Sonnet 4.5",
    "id": "claude-sonnet-4-5"
  },
  "transcript_path": "$TRANSCRIPT",
  "effort": {
    "level": "medium"
  },
  "cost": {
    "total_cost_usd": 0.1234
  },
  "rate_limits": {
    "five_hour": {
      "used_percentage": 20,
      "resets_at": $RESET_5H
    },
    "seven_day": {
      "used_percentage": 36,
      "resets_at": $RESET_7D
    }
  }
}
EOF

echo ""
echo ""
echo "Components shown:"
echo "  - Directory: shortened path"
echo "  - Git: branch and status (if in git repo)"
echo "  - Context: model, percentage, progress bar, tokens used/limit"
echo "  - Cache: ❄ countdown until the prompt cache expires (after the token count)"
echo "  - Cost: session cost in USD"
echo "  - Usage: 5h/7d limits from stdin, with time until reset"
