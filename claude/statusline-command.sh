#!/usr/bin/env bash
# Claude Code statusLine command
# Shows: cyan model name + context usage + account rate-limit usage (when available).

input=$(cat)

PURPLE=$(tput setaf 5 2>/dev/null || printf '\033[1;35m')
CYAN=$(tput setaf 6 2>/dev/null || printf '\033[1;36m')
COLOR_OFF=$(tput sgr0 2>/dev/null || printf '\033[0m')

model=$(echo "$input" | jq -r '.model.display_name // ""')

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
    ctx_str=$(printf " ctx:%.0f%%" "$used")
else
    ctx_str=""
fi

five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_str=""
if [ -n "$five" ] || [ -n "$week" ]; then
    rate_str=" ${PURPLE}|${COLOR_OFF}${CYAN}"
    [ -n "$five" ] && rate_str="${rate_str} 5h:$(printf '%.0f' "$five")%"
    [ -n "$week" ] && rate_str="${rate_str} wk:$(printf '%.0f' "$week")%"
fi

printf "%s%s%s%s%s\n" \
    "$CYAN" "$model" "$ctx_str" "$rate_str" "$COLOR_OFF"
