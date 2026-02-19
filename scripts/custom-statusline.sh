#!/bin/bash
# Custom Claude Code statusline
#
# Format: ▓▓▓▓░░░░░░ 44% · 5h: 18% (~2.3h) · 7d: 78% (~1.2d)
# - Chat context: colored progress bar from local stdin JSON
# - 5h/7d usage: exact values from Anthropic OAuth API (cached for 5 minutes)
#
# Authentication:
#   The script reads your OAuth token from the macOS Keychain (or ~/.claude/.credentials.json
#   on Linux). This token is created automatically when you run `claude` and log in via browser.
#   If the token is missing, the statusline shows "setup: claude auth" as a hint.

# Read stdin JSON from Claude Code
input=$(cat)

# --- Color definitions ---
YELLOW='\033[38;5;179m'  # Dimmed yellow (256-color)
ORANGE='\033[38;5;173m'  # Dimmed orange (256-color)
RED='\033[38;5;167m'     # Dimmed red (256-color)
LIGHT_GRAY='\033[38;5;246m' # Subtle gray (256-color, moderately dimmed)
RESET='\033[0m'

# --- Cache ---
USAGE_CACHE="$HOME/.claude/statusline-usage-cache.json"
USAGE_CACHE_MAX_AGE=300  # seconds (5 minutes)

# --- Helper: Fetch usage data from Anthropic OAuth API ---
# Returns JSON with five_hour and seven_day utilization/resets_at.
# Caches response for 5 minutes (shared across all sessions via file).
# Returns 0 on success, 1 if no token or API error.
fetch_usage_data() {
    # Check cache: if file exists and is less than 5 minutes old, use it
    if [[ -f "$USAGE_CACHE" ]]; then
        local fetched_at_iso
        fetched_at_iso=$(jq -r '.fetched_at // ""' "$USAGE_CACHE" 2>/dev/null)
        local fetched_at_ts=0
        if [[ -n "$fetched_at_iso" ]]; then
            fetched_at_ts=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$fetched_at_iso" +%s 2>/dev/null || date -u -d "$fetched_at_iso" +%s 2>/dev/null || echo 0)
        fi
        local now_ts
        now_ts=$(date +%s)
        local cache_age=$(( now_ts - fetched_at_ts ))

        if [[ $cache_age -lt $USAGE_CACHE_MAX_AGE ]]; then
            cat "$USAGE_CACHE"
            return 0
        fi
    fi

    # Get OAuth token (macOS Keychain or Linux credentials file)
    local token=""
    if command -v security &>/dev/null; then
        token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
            | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    elif [[ -f "$HOME/.claude/.credentials.json" ]]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
    fi

    if [[ -z "$token" ]]; then
        return 1
    fi

    # Call API (3s timeout to avoid blocking the statusline)
    local response
    response=$(curl -s --max-time 3 \
        "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)

    # Validate response contains expected fields
    if echo "$response" | jq -e '.five_hour' &>/dev/null; then
        # Cache only the fields we need, with fetch timestamp
        local now_iso
        now_iso=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
        echo "$response" | jq --arg ts "$now_iso" '{fetched_at: $ts, five_hour, seven_day}' > "$USAGE_CACHE"
        cat "$USAGE_CACHE"
        return 0
    fi

    # API error — use stale cache as fallback if available
    if [[ -f "$USAGE_CACHE" ]]; then
        cat "$USAGE_CACHE"
        return 0
    fi

    return 1
}

# --- Helper: Format time remaining from ISO 8601 resets_at timestamp ---
# Output: "~2.3h", "~45m", "~1.8d", "now"
format_time_remaining() {
    local resets_at="$1"

    if [[ -z "$resets_at" || "$resets_at" == "null" ]]; then
        echo ""
        return
    fi

    # Strip fractional seconds and normalize to Z suffix for parsing
    local clean_ts="${resets_at%%.*}"
    # Handle +00:00 timezone suffix
    clean_ts="${clean_ts%+*}Z"

    local reset_ts
    # Try macOS date format first, then GNU date
    reset_ts=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$clean_ts" +%s 2>/dev/null)
    if [[ -z "$reset_ts" ]]; then
        reset_ts=$(date -u -d "$resets_at" +%s 2>/dev/null)
    fi

    if [[ -z "$reset_ts" ]]; then
        echo ""
        return
    fi

    local now_ts
    now_ts=$(date +%s)
    local remaining=$(( reset_ts - now_ts ))

    if [[ $remaining -le 0 ]]; then
        echo "now"
        return
    fi

    local total_minutes=$(( remaining / 60 ))
    local total_hours=$(( remaining / 3600 ))

    if [[ $total_hours -ge 24 ]]; then
        local days
        days=$(echo "scale=1; $remaining / 86400" | bc)
        echo "~${days}d"
    elif [[ $total_minutes -ge 60 ]]; then
        local hours
        hours=$(echo "scale=1; $total_minutes / 60" | bc)
        echo "~${hours}h"
    else
        echo "~${total_minutes}m"
    fi
}

# --- Helper: Get color for a percentage (4 levels) ---
color_for_percent() {
    local percent=$1
    if [[ $percent -lt 70 ]]; then
        echo "$LIGHT_GRAY"
    elif [[ $percent -lt 80 ]]; then
        echo "$YELLOW"
    elif [[ $percent -lt 90 ]]; then
        echo "$ORANGE"
    else
        echo "$RED"
    fi
}

# --- Helper: Get color for usage, considering elapsed time ---
# If usage% < elapsed%, the rate is sustainable — stay gray.
# Args: $1=usage_percent, $2=resets_at (ISO 8601), $3=window_seconds (18000 or 604800)
color_for_usage() {
    local usage_pct=$1
    local resets_at="$2"
    local window_secs=$3

    if [[ -n "$resets_at" && "$resets_at" != "null" ]]; then
        local clean_ts="${resets_at%%.*}"
        clean_ts="${clean_ts%+*}Z"
        local reset_ts
        reset_ts=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$clean_ts" +%s 2>/dev/null)
        if [[ -z "$reset_ts" ]]; then
            reset_ts=$(date -u -d "$resets_at" +%s 2>/dev/null)
        fi

        if [[ -n "$reset_ts" ]]; then
            local now_ts
            now_ts=$(date +%s)
            local remaining=$(( reset_ts - now_ts ))
            if [[ $remaining -lt 0 ]]; then remaining=0; fi
            local elapsed=$(( window_secs - remaining ))
            local elapsed_pct=$(( elapsed * 100 / window_secs ))

            if [[ $usage_pct -le $elapsed_pct ]]; then
                echo "$LIGHT_GRAY"
                return
            fi
        fi
    fi

    color_for_percent $usage_pct
}

# --- Helper: Create colored progress bar ---
# Returns: colored bar string and color, separated by |
create_progress_bar() {
    local percent=$1
    local width=10
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    local color
    color=$(color_for_percent $percent)

    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="▓"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done

    echo "${color}${bar}|${color}"
}

# ========== MAIN ==========

# --- 1. Chat context (from local stdin JSON) ---
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
CURRENT_USAGE=$(echo "$input" | jq '.context_window.current_usage')

if [[ "$CURRENT_USAGE" != "null" && -n "$CURRENT_USAGE" ]]; then
    # input + cache_creation + cache_read (output tokens excluded from context window)
    CURRENT_TOKENS=$(echo "$CURRENT_USAGE" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    context_percent=$((CURRENT_TOKENS * 100 / CONTEXT_SIZE))

    tokens_k=$(((CURRENT_TOKENS + 999) / 1000))
    context_size_k=$((CONTEXT_SIZE / 1000))

    progress_result=$(create_progress_bar $context_percent)
    progress_bar=$(echo "$progress_result" | cut -d'|' -f1)
    text_color=$(echo "$progress_result" | cut -d'|' -f2)

    context_info="${progress_bar} ${text_color}$(printf "%02d" $context_percent)%${LIGHT_GRAY}"
else
    context_info="awaiting data"
fi

# --- 2. Usage data (from Anthropic OAuth API, cached 5 min) ---
usage_data=$(fetch_usage_data)
api_available=$?

if [[ $api_available -eq 0 ]]; then
    # 5h usage
    five_hour_pct=$(echo "$usage_data" | jq '.five_hour.utilization // 0' | xargs printf "%.0f")
    five_hour_resets=$(echo "$usage_data" | jq -r '.five_hour.resets_at // ""')
    five_hour_time=$(format_time_remaining "$five_hour_resets")

    five_hour_color=$(color_for_usage $five_hour_pct "$five_hour_resets" 18000)
    five_hour_fmt=$(printf "%02d" $five_hour_pct)
    if [[ -n "$five_hour_time" ]]; then
        window_info="5h: ${five_hour_color}${five_hour_fmt}%${LIGHT_GRAY} (${five_hour_time})"
    else
        window_info="5h: ${five_hour_color}${five_hour_fmt}%${LIGHT_GRAY}"
    fi

    # 7d usage
    seven_day_pct=$(echo "$usage_data" | jq '.seven_day.utilization // 0' | xargs printf "%.0f")
    seven_day_resets=$(echo "$usage_data" | jq -r '.seven_day.resets_at // ""')
    seven_day_time=$(format_time_remaining "$seven_day_resets")

    seven_day_color=$(color_for_usage $seven_day_pct "$seven_day_resets" 604800)
    seven_day_fmt=$(printf "%02d" $seven_day_pct)
    if [[ -n "$seven_day_time" ]]; then
        weekly_info="7d: ${seven_day_color}${seven_day_fmt}%${LIGHT_GRAY} (${seven_day_time})"
    else
        weekly_info="7d: ${seven_day_color}${seven_day_fmt}%${LIGHT_GRAY}"
    fi
else
    # No OAuth token or API unreachable
    window_info="5h: ? (setup: claude auth)"
    weekly_info="7d: ?"
fi

# --- 3. Output statusline ---
echo -e "${LIGHT_GRAY}$context_info · $window_info · $weekly_info${RESET}"
