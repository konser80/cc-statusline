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
    sid=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
    (umask 077; mkdir -p "$HOME/.cache" && echo "$input" > "$HOME/.cache/statusline-input-${sid}.json") 2>/dev/null
fi

# All stdin fields in one jq pass — unit separator (\037) keeps empty fields intact
IFS=$'\037' read -r current_dir current size pct MODEL MODEL_ID exceeds_200k cost \
    has_limits pct_5h reset_5h pct_7d reset_7d \
    session_id transcript_path <<< "$(echo "$input" | jq -r '
    [ (.workspace.current_dir // ""),
      ((.context_window.current_usage // {})
        | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)),
      (.context_window.context_window_size // 0),
      (.context_window.used_percentage // 0),
      (.model.display_name // ""),
      (.model.id // ""),
      (.exceeds_200k_tokens // false),
      (.cost.total_cost_usd // 0),
      (.rate_limits != null),
      (.rate_limits.five_hour.used_percentage // ""),
      (.rate_limits.five_hour.resets_at // ""),
      (.rate_limits.seven_day.used_percentage // ""),
      (.rate_limits.seven_day.resets_at // ""),
      (.session_id // ""),
      (.transcript_path // "")
    ] | map(tostring) | join("\u001f")')"

# Git information
git_branch=""
git_status=""
git_remote_icon=""
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
    if [ -n "$git_branch" ]; then
        if git -C "$current_dir" --no-optional-locks diff-index --quiet HEAD 2>/dev/null; then
            git_status="✓"
        else
            git_status="✗"
        fi

        # Remote: ⌀ if none configured, ⇡ if the branch differs from it
        # (ahead, behind, or never pushed — one icon covers all three)
        if [ -z "$(git -C "$current_dir" --no-optional-locks remote 2>/dev/null)" ]; then
            git_remote_icon="${C_GRAY}⌀${C_RESET}"
        else
            upstream=$(git -C "$current_dir" --no-optional-locks rev-parse --abbrev-ref '@{u}' 2>/dev/null)
            if [ -z "$upstream" ]; then
                git_remote_icon="${C_YELLOW}⇡${C_RESET}"
            else
                read -r ahead behind <<< "$(git -C "$current_dir" --no-optional-locks rev-list --left-right --count "HEAD...$upstream" 2>/dev/null)"
                if [ "${ahead:-0}" != "0" ] || [ "${behind:-0}" != "0" ]; then
                    git_remote_icon="${C_YELLOW}⇡${C_RESET}"
                fi
            fi
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

# Model — drop any "provider/" prefix, strip the parenthesised suffix, then
# lowercase (bash 3.2 has no ${x,,}). Claude Code normalizes display_name to a
# bare "Opus 5.5"/"GLM 5.2" with no provider prefix, so the slash heuristic
# doesn't work; use model.id instead — Anthropic ids start with "claude-",
# OpenRouter-routed ones (e.g. "z-ai/glm-5.2") don't. Mark those with ⤳.
model_stripped="${MODEL##*/}"
model_icon=""
[[ "$MODEL_ID" != claude-* && -n "$MODEL_ID" ]] && model_icon="⤳ "
model_part="$(echo "${model_stripped%% (*}" | tr '[:upper:]' '[:lower:]')"

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

context_part=$(printf " ${SEPARATOR} ${C_GRAY}${model_icon}${model_part} ${pct_color}${pct}%%${C_GRAY} ${progress_bar} ${usage_color}${current_fmt}/${size_fmt}")

# Build status line components

if [ -n "$git_branch" ]; then
    # Branch name is data too — same reason as dir_part above
    if [ "$git_status" = "✓" ]; then
        status_color="$C_GREEN"
    else
        status_color="$C_RED"
    fi
    remote_suffix=""
    [ -n "$git_remote_icon" ] && remote_suffix=$(printf '%b' "$git_remote_icon")
    git_part=$(printf ' %b %bgit:%s %b%s%b%s' "$SEPARATOR" "$C_GRAY" "$git_branch" "$status_color" "$git_status" "$C_RESET" "$remote_suffix")
else
    git_part=""
fi

# ── OpenRouter session cost (generation API — what was actually billed) ──
# Claude Code's cost.total_cost_usd is priced against its own Anthropic rate
# card and is wrong for OpenRouter-routed models, and so is tokens × catalog
# price: for one z-ai/glm-5.2 session Claude Code said $11.11, the
# /api/v1/models prices gave $0.76, OpenRouter billed $4.88. So we ask
# OpenRouter per response: the transcript (and its subagents' transcripts) holds
# every response id ("gen-…"), and /api/v1/generation?id= returns its
# total_cost. The per-session cache holds one "<gen_id> <cost>" line per
# response; renders sum it as is while new ids are fetched in the background, so
# the figure trails the last response by one render (same pattern as the Fable
# limit below). Requests made outside the transcript (e.g. title generation)
# are not counted.
OR_COST_DIR="$HOME/.cache/statusline-openrouter-cost"
OR_BATCH=50   # ids per background pass

# Never hand an Anthropic credential to OpenRouter: the generic auth token is
# used only when the session is pointed at OpenRouter.
or_key="$OPENROUTER_CC_KEY"
[[ -z "$or_key" && "$ANTHROPIC_BASE_URL" == *openrouter.ai* ]] && or_key="$ANTHROPIC_AUTH_TOKEN"

or_transcripts() {
    printf '%s\n' "$transcript_path"
    local f
    for f in "${transcript_path%.jsonl}"/subagents/*.jsonl; do
        [[ -f "$f" ]] && printf '%s\n' "$f"
    done
}

# stdin: ids, one per line → those with no row in cache file $1
or_unseen() {
    awk -v c="$1" 'BEGIN { while ((getline l < c) > 0) { split(l, a, " "); seen[a[1]] } }
                   NF && !($1 in seen)'
}

refresh_openrouter_cost() {
    local cache="$1" lock="$1.lock"
    # A pass can outlive the usual 1 min (OR_BATCH sequential requests + a retry)
    [[ -n "$(find "$lock" -maxdepth 0 -mmin +3 2>/dev/null)" ]] && rmdir "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || return
    (
        trap 'rmdir "$lock" 2>/dev/null; rm -f "$cache.tmp" "$cache.stamp"' EXIT
        umask 077
        # Anything written to a transcript after this point must trigger another pass
        : > "$cache.stamp"
        [[ -f "$cache" ]] || : > "$cache"
        ids=$(or_transcripts | while IFS= read -r f; do
                grep -oE '"id":"gen-[A-Za-z0-9_-]+"' "$f" 2>/dev/null
              done | cut -d'"' -f4 | sort -u)
        pending=$(echo "$ids" | or_unseen "$cache")
        more=""
        [[ $(echo "$pending" | grep -c .) -gt $OR_BATCH ]] && more=1
        pending=$(echo "$pending" | head -n "$OR_BATCH")

        for attempt in 1 2; do
            [[ -z "$pending" ]] && break
            # A generation takes a few seconds to become queryable
            [[ $attempt -eq 2 ]] && sleep 3
            # Key and URLs go through a config on stdin, not argv (visible in ps).
            # No --parallel: it could interleave the bodies on stdout.
            fetched=$({
                    printf 'header = "Authorization: Bearer %s"\n' "$or_key"
                    echo "$pending" | sed 's|.*|url = "https://openrouter.ai/api/v1/generation?id=&"|'
                } | curl -s --fail --max-time 5 -K - 2>/dev/null \
                  | jq -r '.data | select(.total_cost != null) | "\(.id) \(.total_cost)"' 2>/dev/null)
            if [[ -n "$fetched" ]]; then
                { cat "$cache"; echo "$fetched"; } > "$cache.tmp" && mv "$cache.tmp" "$cache"
            fi
            pending=$(echo "$pending" | or_unseen "$cache")
        done

        # Ids still unknown an hour after they were issued (the timestamp is in the
        # id) belong to another key or are gone — record them as 0 instead of
        # asking again on every render.
        if [[ -n "$pending" ]]; then
            now=$(date +%s)
            dead=$(echo "$pending" | awk -F- -v now="$now" '$2 ~ /^[0-9]+$/ && now - $2 > 3600 { print $0, 0 }')
            if [[ -n "$dead" ]]; then
                { cat "$cache"; echo "$dead"; } > "$cache.tmp" && mv "$cache.tmp" "$cache"
                pending=$(echo "$pending" | or_unseen "$cache")
            fi
        fi

        if [[ -z "$pending" && -z "$more" ]]; then
            touch -r "$cache.stamp" "$cache"
        else
            # Work left: age the cache so the next render starts another pass
            touch -t 200001010000 "$cache"
        fi
    ) >/dev/null 2>&1 &
}

read_openrouter_cost() {
    or_cost=""
    # session_id names the cache file — take it only in its expected shape
    [[ -n "$or_key" && -f "$transcript_path" && "$session_id" =~ ^[A-Za-z0-9_-]+$ ]] || return
    (umask 077; mkdir -p "$OR_COST_DIR") 2>/dev/null
    local cache="$OR_COST_DIR/$session_id" f stale=""
    while IFS= read -r f; do
        [[ "$f" -nt "$cache" ]] && stale=1
    done < <(or_transcripts)
    [[ -n "$stale" ]] && refresh_openrouter_cost "$cache"
    [[ -s "$cache" ]] && or_cost=$(awk '{ s += $2 } END { printf "%.4f", s }' "$cache" 2>/dev/null)
}

# Session cost — three cases by token/model:
#  - OpenRouter model (non-claude id): sum of what OpenRouter billed per response
#  - Anthropic API token (sk-ant-api*): show Claude Code's cost.total_cost_usd
#  - Subscription (sk-ant-oat*): hide cost
cost_part=""
token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
if [[ "$MODEL_ID" != claude-* && -n "$MODEL_ID" ]]; then
    read_openrouter_cost
    if [[ -n "$or_cost" ]]; then
        cost_part=$(printf " ${SEPARATOR} ${C_DARK_GRAY}\$%s${C_RESET}" "$or_cost")
    fi
elif [[ "$token" != sk-ant-oat* ]]; then
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
    if [[ $int_pct -gt 90 ]]; then
        color="$C_RED"
    elif [[ $int_pct -gt 70 ]]; then
        color="$C_YELLOW"
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

# ── Fable weekly limit (from the usage API — stdin has no per-model rows) ──
# The cache holds one line "<percent> <resets_at epoch>", or is empty when the
# account has no Fable row. Renders read it as is; a stale cache is refreshed in
# the background so a slow API never delays the status line.
FABLE_CACHE="$HOME/.cache/statusline-fable"
FABLE_LOCK="$HOME/.cache/statusline-fable.lock"

refresh_fable_cache() {
    # Drop a lock left behind by a killed refresh
    [[ -n "$(find "$FABLE_LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]] && rmdir "$FABLE_LOCK" 2>/dev/null
    mkdir "$FABLE_LOCK" 2>/dev/null || return
    (
        trap 'rmdir "$FABLE_LOCK" 2>/dev/null' EXIT
        umask 077
        response=$(curl -s --fail --max-time 5 "https://api.anthropic.com/api/oauth/usage" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20") || exit
        # Cache only a response that has limits[] — an error body must not
        # overwrite good data. Temp file + mv keeps readers from seeing half a write.
        line=$(echo "$response" | jq -er '
            if (.limits | type) != "array" then error("no limits") else
            [ .limits[] | select(.kind == "weekly_scoped" and .scope.model.display_name == "Fable") ][0]
            | if . == null then "" else
                "\(.percent // 0) \(.resets_at // "" | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | (fromdateiso8601? // ""))"
              end
            end') || exit
        echo "$line" > "$FABLE_CACHE.tmp" && mv "$FABLE_CACHE.tmp" "$FABLE_CACHE"
    ) >/dev/null 2>&1 &
}

read_fable_limit() {
    pct_fable=""
    reset_fable=""
    mkdir -p "$HOME/.cache" 2>/dev/null
    if [[ -z "$(find "$FABLE_CACHE" -maxdepth 0 -mmin -2 2>/dev/null)" ]]; then
        refresh_fable_cache
    fi
    [[ -f "$FABLE_CACHE" ]] && read -r pct_fable reset_fable < "$FABLE_CACHE"
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
        if [[ "$token" == sk-ant-oat* ]]; then
            read_fable_limit
            if [[ -n "$pct_fable" && "$pct_fable" != "0" ]]; then
                fable_str=$(format_usage_block "fable:" "$pct_fable" "$reset_fable" "days")
                if [[ -n "$limits_output" ]]; then
                    limits_output="${limits_output} ${SEPARATOR} ${fable_str}"
                else
                    limits_output="${fable_str}"
                fi
            fi
        fi
        [[ -n "$limits_output" ]] && usage_part=" ${SEPARATOR} ${limits_output}"
    fi
fi

# Print complete status line
echo -e -n "${dir_part}${git_part}${context_part}${cost_part}${usage_part}"
