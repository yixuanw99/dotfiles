#!/bin/bash
input=$(cat)

# PS1-derived: user@host:dir
user=$(whoami)
host=$(hostname -s)

# Directory: Antigravity provides .workspace.current_dir or .cwd; fallback to pwd
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$dir" ] && dir=$(pwd)
dir="${dir/#$HOME/\~}"

# Model info: display_name and effort
model=$(echo "$input" | jq -r '.model.display_name // .model.id // empty')
effort=$(echo "$input" | jq -r '.model.effort // empty')
if [ -n "$model" ] && [ -n "$effort" ]; then
  model_display="${model} (${effort})"
else
  model_display="${model}"
fi

# Plan Tier (e.g. Enterprise, Pro)
plan_tier=$(echo "$input" | jq -r '.plan_tier // empty')

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

# Git / VCS branch (Antigravity provides .vcs.branch and .vcs.dirty natively)
git_branch=$(echo "$input" | jq -r '.vcs.branch // empty')
is_dirty=$(echo "$input" | jq -r '.vcs.dirty // empty')
if [ -z "$git_branch" ]; then
  target_cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
  if git -C "$target_cwd" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$target_cwd" branch --show-current 2>/dev/null)
  fi
fi
if [ -n "$git_branch" ] && [ "$is_dirty" = "true" ]; then
  git_branch="${git_branch}*"
fi

# Quota / Rate limits
rate_part=""
reset_part=""

# 1. Antigravity Quota map: .quota
quota_json=$(echo "$input" | jq -c '.quota // empty')
if [ -n "$quota_json" ] && [ "$quota_json" != "{}" ] && [ "$quota_json" != "null" ]; then
  buckets_summary=$(echo "$quota_json" | jq -r '
    to_entries | map(
      select(.value != null) |
      (if .value.remaining_fraction != null then ((1.0 - .value.remaining_fraction) * 100 | round | tostring) + "%" else null end) as $pct |
      {
        key: .key,
        used_pct: $pct,
        reset_in_seconds: (.value.reset_in_seconds // null),
        reset_time: (.value.reset_time // null)
      }
    )
  ')

  count=$(echo "$buckets_summary" | jq 'length')
  if [ "$count" -eq 1 ]; then
    pct=$(echo "$buckets_summary" | jq -r '.[0].used_pct // empty')
    [ -n "$pct" ] && rate_part="Quota: ${pct}"
    ris=$(echo "$buckets_summary" | jq -r '.[0].reset_in_seconds // empty')
    if [ -n "$ris" ] && [ "$ris" -gt 0 ] 2>/dev/null; then
      hrs=$((ris / 3600))
      mins=$(( (ris % 3600) / 60 ))
      reset_part="Reset: ${hrs} hr ${mins} min"
    fi
  elif [ "$count" -gt 1 ]; then
    # Multiple buckets: display each used percentage
    rate_part=$(echo "$buckets_summary" | jq -r '
      map(select(.used_pct != null) | "\(.key): \(.used_pct)") | join(" / ")
    ')
    # Find minimum positive reset_in_seconds
    min_ris=$(echo "$buckets_summary" | jq -r '
      map(.reset_in_seconds | select(. != null and . > 0)) | min // empty
    ')
    if [ -n "$min_ris" ] && [ "$min_ris" -gt 0 ] 2>/dev/null; then
      hrs=$((min_ris / 3600))
      mins=$(( (min_ris % 3600) / 60 ))
      reset_part="Reset: ${hrs} hr ${mins} min"
    fi
  fi
fi

# 2. Fallback to Claude Code format: .rate_limits
if [ -z "$rate_part" ]; then
  five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
  week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
  five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

  if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
    bits=""
    [ -n "$five_pct" ] && bits="5h: $(printf '%.0f' "$five_pct")%"
    if [ -n "$week_pct" ]; then
      [ -n "$bits" ] && bits="${bits} / "
      bits="${bits}7d: $(printf '%.0f' "$week_pct")%"
    fi
    rate_part="$bits"
  fi

  if [ -n "$five_reset" ] && [ -z "$reset_part" ]; then
    now=$(date +%s)
    diff=$((five_reset - now))
    if [ "$diff" -gt 0 ]; then
      hrs=$((diff / 3600))
      mins=$(( (diff % 3600) / 60 ))
      reset_part="Reset: ${hrs} hr ${mins} min"
    fi
  fi
fi

# Optional Cost (if reported by Antigravity)
cost_val=$(echo "$input" | jq -r '.cost.total_usd // empty')
cost_part=""
if [ -n "$cost_val" ] && [ "$cost_val" != "null" ]; then
  if awk "BEGIN {exit !($cost_val > 0)}" 2>/dev/null; then
    cost_part=$(printf '$%.2f' "$cost_val")
  fi
fi

# Colors
WHITE='\033[37m'
GREEN='\033[32m'
BLUE='\033[34m'
ORANGE='\033[38;5;208m'
CYAN='\033[36m'
R='\033[0m'

# Line 1: (env)user@host:dir | ⎇ branch | [Model (effort)] [Tier]
line1=""
[ -n "$conda_part" ] && line1="${WHITE}${conda_part}${R} "
line1="${line1}${GREEN}${user}@${host}${R}:${BLUE}${dir}${R}"
[ -n "$git_branch" ] && line1="${line1} | ⎇ ${git_branch}"
[ -n "$model_display" ] && line1="${line1} | ${ORANGE}[${model_display}]${R}"
[ -n "$plan_tier" ] && line1="${line1} | ${CYAN}[${plan_tier}]${R}"

# Line 2: ░░░░░░░░░░ 6% | Quota: 28% | Reset: 2 hr 2 min | $0.05
line2="${BAR} ${used_pct}%"
[ -n "$rate_part" ] && line2="${line2} | ${rate_part}"
[ -n "$reset_part" ] && line2="${line2} | ${reset_part}"
[ -n "$cost_part" ] && line2="${line2} | ${cost_part}"

printf '%b\n' "$line1"
echo "$line2"
