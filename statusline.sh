#!/bin/bash

C_DARK_CYAN="\033[38;5;30m"
C_DARK_GRAY="\033[38;5;240m"
C_GRAY="\033[38;5;8m"
C_BLUE="\033[38;5;4m"
C_GREEN="\033[38;5;2m"
C_YELLOW="\033[38;5;220m"
C_RED="\033[38;5;203m"
C_CYAN="\033[38;5;81m"
C_LIGHT_GREEN="\033[38;5;78m"
C_RESET="\033[0m"

SEPARATOR="${C_DARK_GRAY}|${C_RESET}"

# Read JSON input from stdin
input=$(cat)

# Dump raw input for debugging
echo "$input" > /tmp/statusline-input.json

# Extract current directory
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')

# Git information
git_branch=""
git_status=""
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
    if [ -n "$git_branch" ]; then
        if git -C "$current_dir" --no-optional-locks diff-index --quiet HEAD 2>/dev/null; then
            git_status="✓"
        else
            git_status="✗"
        fi
    fi
fi

# folder
# Shorten directory path and split for coloring
short_dir=$(echo "$current_dir" | awk -F'/' '{n = NF; if (n <= 3) print $0; else printf "%s/%s/%s", $(n-2), $(n-1), $n}')
# Split into parent path (gray) and current dir (blue)
dir_parent=$(dirname "$short_dir")
dir_name=$(basename "$short_dir")
dir_part=$(printf " ${C_DARK_GRAY}${dir_parent}/${C_BLUE}${dir_name}${C_RESET}")


# Context window usage
context_part=""
usage=$(echo "$input" | jq '.context_window.current_usage')
size=$(echo "$input" | jq '.context_window.context_window_size')

if [ "$usage" != "null" ]; then
    current=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
else
    # Zero state - no messages yet
    current=0
fi

# Percentage from Claude Code (of full context window)
pct=$(echo "$input" | jq '.context_window.used_percentage')

# Format total size (1M for 1000k, otherwise Nk)
if [ $((size / 1000)) -ge 1000 ]; then
    size_fmt="$((size / 1000000))M"
else
    size_fmt="$((size / 1000))k"
fi
# Format current tokens
if [ $current -ge 1000 ]; then
    current_fmt="$((current / 1000))k"
else
    current_fmt="$current"
fi
# Dynamic color based on percentage
if [ $pct -gt 80 ]; then
    pct_color="$C_RED"
elif [ $pct -gt 60 ]; then
    pct_color="$C_YELLOW"
else
    pct_color="$C_GREEN"
fi

# Model
MODEL=$(echo "$input" | jq -r '.model.display_name')
model_part="$(echo "$MODEL" | sed 's/ *(.*//' | tr '[:upper:]' '[:lower:]')"

# Progress bar (10 chars wide)
bar_width=10
filled=$((pct * bar_width / 100))
empty=$((bar_width - filled))
# Clamp values
[ $filled -gt $bar_width ] && filled=$bar_width
[ $filled -lt 0 ] && filled=0
[ $empty -lt 0 ] && empty=0

bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '▓')
bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '░')
progress_bar="${pct_color}${bar_filled}${pct_color}${bar_empty}${C_RESET}"

exceeds_200k=$(echo "$input" | jq -r '.exceeds_200k_tokens')
if [ "$exceeds_200k" = "true" ]; then
    usage_color="$C_YELLOW"
else
    usage_color="$C_GRAY"
fi

context_part=$(printf " ${SEPARATOR} ${C_GRAY}$model_part ${pct_color}${pct}%%${C_GRAY} ${progress_bar} ${usage_color}${current_fmt}/${size_fmt}")

# Build status line components

if [ -n "$git_branch" ]; then
    if [ "$git_status" = "✓" ]; then
        git_part=$(printf " ${SEPARATOR} ${C_GRAY}git:${git_branch} ${C_GREEN}${git_status}${C_RESET}")
    else
        git_part=$(printf " ${SEPARATOR} ${C_GRAY}git:${git_branch} ${C_RED}${git_status}${C_RESET}")
    fi
else
    git_part=""
fi

# Session cost (skip for subscription users — OAuth token starts with sk-ant-oat)
cost_part=""
token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
if [[ "$token" != sk-ant-oat* ]]; then
    cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
    if [ "$cost" != "0" ] && [ "$cost" != "null" ]; then
        cost_fmt=$(printf "%.4f" "$cost")
        cost_part=$(printf " ${SEPARATOR} ${C_DARK_GRAY}\$${cost_fmt}${C_RESET}")
    fi
fi

# ── Claude API usage limits ──────────────────────────────────────────

CACHE_DIR="$HOME/.cache"
API_CACHE_FILE="$CACHE_DIR/claude-api-response.json"
LOCK_FILE="$CACHE_DIR/claude-usage.lock"
CACHE_TTL=120
RATE_LIMIT=60

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

    # Reuse token from subscription check above
    local api_token="$token"
    [[ -z "$api_token" ]] && { [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"; return 0; }

    local response=$(curl -s --max-time 5 "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $api_token" \
        -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)

    if [[ -n "$response" ]]; then
        echo "$response" | tee "$API_CACHE_FILE"
    else
        [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"
    fi
}

format_usage_block() {
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

usage_part=""
RESPONSE=$(fetch_api_data)

if [[ -n "$RESPONSE" ]]; then
    session=$(echo "$RESPONSE" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
    weekly=$(echo "$RESPONSE" | jq -r '.seven_day.utilization // empty' 2>/dev/null)

    if [[ -z "$session" && -z "$weekly" ]]; then
        # Max subscription - no limits
        usage_part=" ${SEPARATOR} ${C_GREEN}∞${C_RESET}"
    else
        limits_output=""
        if [[ -n "$session" ]]; then
            session_reset=$(echo "$RESPONSE" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
            limits_output=$(format_usage_block "5h:" "$session" "$session_reset" "")
        fi
        if [[ -n "$weekly" ]]; then
            weekly_reset=$(echo "$RESPONSE" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
            weekly_str=$(format_usage_block "7d:" "$weekly" "$weekly_reset" "days")
            if [[ -n "$limits_output" ]]; then
                limits_output="${limits_output} ${SEPARATOR} ${weekly_str}"
            else
                limits_output="${weekly_str}"
            fi
        fi
        [[ -n "$limits_output" ]] && usage_part=" ${SEPARATOR} ${limits_output}"
    fi
fi

# Print complete status line
echo -e -n "${dir_part}${git_part}${context_part}${cost_part}${usage_part}"
