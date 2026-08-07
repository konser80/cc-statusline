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

# Dump raw input for debugging — off by default: this JSON carries session_id,
# cwd and transcript_path, so it must not land in a world-readable /tmp file.
if [[ -n "$STATUSLINE_DEBUG" ]]; then
    (umask 077; echo "$input" > "$HOME/.cache/statusline-input.json")
fi

# All stdin fields in one jq pass — unit separator (\037) keeps empty fields intact
IFS=$'\037' read -r current_dir current size pct MODEL exceeds_200k cost \
    has_limits pct_5h reset_5h pct_7d reset_7d <<< "$(echo "$input" | jq -r '
    [ (.workspace.current_dir // ""),
      ((.context_window.current_usage // {})
        | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)),
      (.context_window.context_window_size // 0),
      (.context_window.used_percentage // 0),
      (.model.display_name // ""),
      (.exceeds_200k_tokens // false),
      (.cost.total_cost_usd // 0),
      (.rate_limits != null),
      (.rate_limits.five_hour.used_percentage // ""),
      (.rate_limits.five_hour.resets_at // ""),
      (.rate_limits.seven_day.used_percentage // ""),
      (.rate_limits.seven_day.resets_at // "")
    ] | map(tostring) | join("\u001f")')"

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
# Directory name goes in printf's arguments, never in the format string — a '%' in
# a path would otherwise be read as a conversion specifier
dir_part=$(printf ' %b%s/%b%s%b' "$C_DARK_GRAY" "$dir_parent" "$C_BLUE" "$dir_name" "$C_RESET")


# Context window usage
context_part=""

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

# Model — strip the parenthesised suffix, then lowercase (bash 3.2 has no ${x,,})
model_part="$(echo "${MODEL%% (*}" | tr '[:upper:]' '[:lower:]')"

# Progress bar (10 chars wide)
bar_width=10
filled=$((pct * bar_width / 100))
empty=$((bar_width - filled))
# Clamp values
[ $filled -gt $bar_width ] && filled=$bar_width
[ $filled -lt 0 ] && filled=0
[ $empty -lt 0 ] && empty=0

bar_filled=""; for ((i=0; i<filled; i++)); do bar_filled+='▓'; done
bar_empty="";  for ((i=0; i<empty;  i++)); do bar_empty+='░';  done
progress_bar="${pct_color}${bar_filled}${pct_color}${bar_empty}${C_RESET}"

if [ "$exceeds_200k" = "true" ]; then
    usage_color="$C_YELLOW"
else
    usage_color="$C_GRAY"
fi

context_part=$(printf " ${SEPARATOR} ${C_GRAY}$model_part ${pct_color}${pct}%%${C_GRAY} ${progress_bar} ${usage_color}${current_fmt}/${size_fmt}")

# Build status line components

if [ -n "$git_branch" ]; then
    # Branch name is data too — same reason as dir_part above
    if [ "$git_status" = "✓" ]; then
        status_color="$C_GREEN"
    else
        status_color="$C_RED"
    fi
    git_part=$(printf ' %b %bgit:%s %b%s%b' "$SEPARATOR" "$C_GRAY" "$git_branch" "$status_color" "$git_status" "$C_RESET")
else
    git_part=""
fi

# Session cost (skip for subscription users — OAuth token starts with sk-ant-oat)
cost_part=""
token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
if [[ "$token" != sk-ant-oat* ]]; then
    if [ "$cost" != "0" ] && [ "$cost" != "null" ]; then
        cost_fmt=$(printf "%.4f" "$cost")
        cost_part=$(printf " ${SEPARATOR} ${C_DARK_GRAY}\$${cost_fmt}${C_RESET}")
    fi
fi

# ── Claude usage limits (from stdin) ─────────────────────────────────

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
        local secs_left=$((reset_at - $(date +%s)))
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

if [ "$has_limits" = "true" ]; then
    if [[ -z "$pct_5h" && -z "$pct_7d" ]]; then
        # Max subscription - no limits
        usage_part=" ${SEPARATOR} ${C_GREEN}∞${C_RESET}"
    else
        limits_output=""
        if [[ -n "$pct_5h" ]]; then
            limits_output=$(format_usage_block "5h:" "$pct_5h" "$reset_5h" "")
        fi
        if [[ -n "$pct_7d" ]]; then
            weekly_str=$(format_usage_block "7d:" "$pct_7d" "$reset_7d" "days")
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
