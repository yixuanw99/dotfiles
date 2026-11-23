#!/bin/bash
input=$(cat)

# Colors
ESC=$'\033'
WHITE="${ESC}[37m"
GREEN="${ESC}[32m"
BLUE="${ESC}[34m"
ORANGE="${ESC}[38;5;208m"
RED="${ESC}[31m"
R="${ESC}[0m"

# PS1-derived: user@host:dir
user=$(whoami)
host=$(hostname -s)
dir=$(echo "$input" | jq -r '.cwd // empty')
[ -z "$dir" ] && dir=$(pwd)
dir="${dir/#$HOME/\~}"

# Model display name
model=$(echo "$input" | jq -r '.model.display_name // empty')

# Context window info
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
[ -z "$used_pct" ] && used_pct=0
# Tokens currently in context = input + cache_creation + cache_read (same basis as used_percentage)
ctx_used=$(echo "$input" | jq -r '(.context_window.current_usage // {}) | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
fmt_k() { echo "$(( ($1 + 500) / 1000 ))k"; }

# Progress bar (10 cells). Both filled and empty cells are background-colored spaces:
# no glyphs at all, so they cannot misalign or overflow the line height. (Block/shade
# characters like ░ ▒ ▓ █ rendered taller than the line in some fonts and overlapped
# the line above.)
BAR_WIDTH=10
FILLED=$((used_pct * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
if [ "$used_pct" -ge 80 ]; then
  FILL_BG="${ESC}[48;5;203m"   # red warning
  PCT_COLOR="$RED"
else
  FILL_BG="${ESC}[48;5;114m"   # soft green
  PCT_COLOR=""
fi
EMPTY_BG="${ESC}[48;5;240m"    # dark gray
BAR=""
if [ "$FILLED" -gt 0 ]; then
  printf -v FILL "%${FILLED}s"
  BAR="${FILL_BG}${FILL}${R}"
fi
if [ "$EMPTY" -gt 0 ]; then
  printf -v PAD "%${EMPTY}s"
  BAR="${BAR}${EMPTY_BG}${PAD}${R}"
fi

# Conda env
conda_part=""
[ -n "$CONDA_DEFAULT_ENV" ] && conda_part="(${CONDA_DEFAULT_ENV})"

# Git branch
git_branch=""
if git -C "$(echo "$input" | jq -r '.cwd // "."')" rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git -C "$(echo "$input" | jq -r '.cwd // "."')" branch --show-current 2>/dev/null)
fi

# Rate limits with decimals
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

rate_part=""
if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
  bits=""
  [ -n "$five_pct" ] && bits="5h: $(printf '%.0f' "$five_pct")%"
  if [ -n "$week_pct" ]; then
    [ -n "$bits" ] && bits="${bits} / "
    bits="${bits}7d: $(printf '%.0f' "$week_pct")%"
  fi
  rate_part="$bits"
fi

# Reset countdown (use 5h window)
reset_part=""
if [ -n "$five_reset" ]; then
  now=$(date +%s)
  diff=$((five_reset - now))
  if [ "$diff" -gt 0 ]; then
    hrs=$((diff / 3600))
    mins=$(( (diff % 3600) / 60 ))
    reset_part="Reset: ${hrs} hr ${mins} min"
  fi
fi

# Line 1: (env)user@host:dir | ⎇ branch | [Model]
line1=""
[ -n "$conda_part" ] && line1="${WHITE}${conda_part}${R} "
line1="${line1}${GREEN}${user}@${host}${R}:${BLUE}${dir}${R}"
[ -n "$git_branch" ] && line1="${line1} | ⎇ ${git_branch}"
[ -n "$model" ] && line1="${line1} | ${ORANGE}[${model}]${R}"

# Line 2: ░░░░░░░░░░ 6% (12k/200k) | 5h: 63% / 7d: 20% | Reset: 3 hr 16 min
pct_txt="${used_pct}%"
if [ "$ctx_size" -gt 0 ]; then
  pct_txt="${pct_txt} ($(fmt_k "$ctx_used")/$(fmt_k "$ctx_size"))"
fi
[ -n "$PCT_COLOR" ] && pct_txt="${PCT_COLOR}${pct_txt}${R}"
line2="${BAR} ${pct_txt}"
[ -n "$rate_part" ] && line2="${line2} | ${rate_part}"
[ -n "$reset_part" ] && line2="${line2} | ${reset_part}"

printf '%b\n' "$line1"
printf '%b\n' "$line2"
