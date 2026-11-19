#!/bin/bash
input=$(cat)

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

# Build progress bar (10 chars)
BAR_WIDTH=10
FILLED=$((used_pct * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
if [ "$FILLED" -gt 0 ]; then
  printf -v FILL "%${FILLED}s"
  BAR="${FILL// /▓}"
fi
if [ "$EMPTY" -gt 0 ]; then
  printf -v PAD "%${EMPTY}s"
  BAR="${BAR}${PAD// /░}"
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

# Colors
WHITE='\033[37m'
GREEN='\033[32m'
BLUE='\033[34m'
ORANGE='\033[38;5;208m'
R='\033[0m'

# Line 1: (env)user@host:dir | ⎇ branch | [Model]
line1=""
[ -n "$conda_part" ] && line1="${WHITE}${conda_part}${R} "
line1="${line1}${GREEN}${user}@${host}${R}:${BLUE}${dir}${R}"
[ -n "$git_branch" ] && line1="${line1} | ⎇ ${git_branch}"
[ -n "$model" ] && line1="${line1} | ${ORANGE}[${model}]${R}"

# Line 2: ░░░░░░░░░░ 6% | 5h: 63% / 7d: 20% | Reset: 3 hr 16 min
line2="${BAR} ${used_pct}%"
[ -n "$rate_part" ] && line2="${line2} | ${rate_part}"
[ -n "$reset_part" ] && line2="${line2} | ${reset_part}"

printf '%b\n' "$line1"
echo "$line2"
