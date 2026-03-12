#!/bin/bash

# Compact version for statusline integration
# Returns formatted usage string compatible with statusline.sh colors

# Cache configuration
CACHE_TTL=120        # Cache TTL in seconds
RATE_LIMIT=60       # Minimum seconds between API requests

CACHE_DIR="$HOME/.cache"
API_CACHE_FILE="$CACHE_DIR/claude-api-response.json"
LOCK_FILE="$CACHE_DIR/claude-usage.lock"

# Use same color scheme as statusline.sh
C_GREEN="\033[38;5;2m"
C_YELLOW="\033[38;5;220m"
C_RED="\033[38;5;203m"
C_GRAY="\033[38;5;8m"
C_LIGHT="\033[38;5;7m"
C_RESET="\033[0m"
C_DARK_GRAY="\033[38;5;240m"
SEPARATOR="${C_DARK_GRAY}|${C_RESET}"

[[ ! -d "$CACHE_DIR" ]] && mkdir -p "$CACHE_DIR"

get_file_age() {
  local file="$1"
  local mod_time=$(stat -f '%m' "$file" 2>/dev/null)
  local now=$(date +%s)
  echo $((now - mod_time))
}

parse_iso_to_seconds_left() {
  local iso_date="$1"
  local clean_date=$(echo "$iso_date" | sed 's/\.[0-9]*//; s/+00:00//; s/Z$//')
  local reset_ts=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$clean_date" "+%s" 2>/dev/null)
  if [[ -n "$reset_ts" ]]; then
    local now=$(date +%s)
    echo $((reset_ts - now))
  else
    echo "0"
  fi
}

format_remaining_time() {
  local seconds="$1"
  if [[ $seconds -le 0 ]]; then
    echo ""
    return
  fi
  local hours=$((seconds / 3600))
  local mins=$(((seconds % 3600) / 60))
  if [[ $hours -gt 0 ]]; then
    echo "${hours}h${mins}m"
  else
    echo "${mins}m"
  fi
}

format_remaining_time_days() {
  local seconds="$1"
  if [[ $seconds -le 0 ]]; then
    echo ""
    return
  fi
  local days=$((seconds / 86400))
  local hours=$(((seconds % 86400) / 3600))
  if [[ $days -gt 0 ]]; then
    echo "${days}d${hours}h"
  else
    format_remaining_time "$seconds"
  fi
}

# Fetch API data with caching
fetch_api_data() {
  if [[ -f "$API_CACHE_FILE" ]]; then
    local age=$(get_file_age "$API_CACHE_FILE")
    if [[ $age -lt $CACHE_TTL ]]; then
      cat "$API_CACHE_FILE"
      return 0
    fi
  fi

  if [[ -f "$LOCK_FILE" ]]; then
    local lock_age=$(get_file_age "$LOCK_FILE")
    if [[ $lock_age -lt $RATE_LIMIT ]]; then
      [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"
      return 0
    fi
  fi
  touch "$LOCK_FILE"

  local keychain_data=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  [[ -z "$keychain_data" ]] && { [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"; return 0; }

  local token=$(echo "$keychain_data" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  [[ -z "$token" ]] && { [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"; return 0; }

  local response=$(curl -s --max-time 5 "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)

  if [[ -n "$response" ]]; then
    echo "$response" | tee "$API_CACHE_FILE"
  else
    [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"
  fi
}

RESPONSE=$(fetch_api_data)
[[ -z "$RESPONSE" ]] && exit 0

session=$(echo "$RESPONSE" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
weekly=$(echo "$RESPONSE" | jq -r '.seven_day.utilization // empty' 2>/dev/null)

# Max subscription - no limits
if [[ -z "$session" && -z "$weekly" ]]; then
  printf "${C_GREEN}∞${C_RESET}"
  exit 0
fi

# Format full usage block with consistent color
format_block() {
  local label="$1"
  local pct="$2"
  local reset_at="$3"
  local use_days="$4"
  local int_pct=${pct%.*}

  local color
  if [[ $int_pct -gt 80 ]]; then
    color="$C_RED"
  elif [[ $int_pct -gt 60 ]]; then
    color="$C_YELLOW"
  elif [[ $int_pct -gt 40 ]]; then
    color="$C_GRAY"
  else
    color="$C_DARK_GRAY"
  fi

  local time_str=""
  if [[ -n "$reset_at" ]]; then
    local secs_left=$(parse_iso_to_seconds_left "$reset_at")
    if [[ "$use_days" == "days" ]]; then
      time_str=$(format_remaining_time_days "$secs_left")
    else
      time_str=$(format_remaining_time "$secs_left")
    fi
  fi

  if [[ -n "$time_str" ]]; then
    printf "${color}${label}${int_pct}%% (${time_str})${C_RESET}"
  else
    printf "${color}${label}${int_pct}%%${C_RESET}"
  fi
}

output=""

if [[ -n "$session" ]]; then
  session_reset=$(echo "$RESPONSE" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
  output=$(format_block "5h:" "$session" "$session_reset" "")
fi

if [[ -n "$weekly" ]]; then
  weekly_reset=$(echo "$RESPONSE" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
  weekly_str=$(format_block "7d:" "$weekly" "$weekly_reset" "days")
  if [[ -n "$output" ]]; then
    output="${output} ${SEPARATOR} ${weekly_str}"
  else
    output="${weekly_str}"
  fi
fi

printf "%b" "$output"
