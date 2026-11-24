#!/bin/bash
input=$(cat)

# Parse all fields from JSON in a single jq invocation (one field per line).
mapfile -t _f < <(jq -r '
  def clean: tostring | gsub("[\r\n\t]+"; " ");
  def fmt_epoch_rem:
    (. - now) | if . > 0 then floor else empty end;
  def fmt_pct:
    ((1.0 - .) * 100) | round | tostring + "%";

  [
    (.workspace.current_dir // .cwd // ""),
    (.model.display_name // .model.id // ""),
    (.model.effort // ""),
    (.plan_tier // ""),
    ((.context_window.used_percentage // 0) | floor),
    ((.context_window.context_window_size // 0) | floor),
    (.vcs.branch // ""),
    (.vcs.dirty // ""),
    (
      if (.quota? | type) == "object" and (.quota | length) > 0 then
        (.quota | to_entries | map(select(.value != null and .value.remaining_fraction != null))) as $entries |
        if ($entries | length) == 1 and ($entries[0].key | IN("gemini-5h", "gemini-weekly") | not) then
          "Quota: " + ($entries[0].value.remaining_fraction | fmt_pct)
        else
          [
            (["gemini-5h", "gemini-weekly"][] as $k |
              ($entries[] | select(.key == $k)) | "\(.key): \(.value.remaining_fraction | fmt_pct)")
          ] | join(" / ")
        end
      elif .rate_limits? then
        [
          (if .rate_limits.five_hour.used_percentage? != null then "5h: " + (.rate_limits.five_hour.used_percentage | round | tostring) + "%" else empty end),
          (if .rate_limits.seven_day.used_percentage? != null then "7d: " + (.rate_limits.seven_day.used_percentage | round | tostring) + "%" else empty end)
        ] | join(" / ")
      else "" end
    ),
    (
      if (.quota? | type) == "object" and (.quota | length) > 0 then
        (.quota | to_entries | map(select(.value != null and .value.remaining_fraction != null))) as $entries |
        if ($entries | length) == 1 and ($entries[0].key | IN("gemini-5h", "gemini-weekly") | not) then
          ""
        else
          [
            $entries[] | select(.key | IN("gemini-5h", "gemini-weekly") | not) |
            "\(.key): \(.value.remaining_fraction | fmt_pct)"
          ] | join(" / ")
        end
      else "" end
    ),
    (
      if (.quota? | type) == "object" and (.quota | length) > 0 then
        ([.quota[]? | .reset_in_seconds? | select(. != null and . > 0)] | min // "")
      elif .rate_limits.five_hour.resets_at? != null then
        (.rate_limits.five_hour.resets_at | fmt_epoch_rem // "")
      else "" end
    ),
    (if .cost.total_usd? != null and (.cost.total_usd | tonumber? // 0) > 0 then .cost.total_usd else "" end),
    ((.terminal_width // 0) | floor)
  ] | .[] | clean
' <<< "$input" 2>/dev/null)

dir="${_f[0]:-}"
model="${_f[1]:-}"
effort="${_f[2]:-}"
plan_tier="${_f[3]:-}"
used_pct="${_f[4]:-0}"
ctx_size="${_f[5]:-0}"
git_branch="${_f[6]:-}"
is_dirty="${_f[7]:-}"
primary_rate="${_f[8]:-}"
other_rate="${_f[9]:-}"
reset_secs="${_f[10]:-}"
cost_val="${_f[11]:-}"
term_width="${_f[12]:-0}"

[[ "$used_pct" =~ ^[0-9]+$ ]] || used_pct=0
[[ "$ctx_size" =~ ^[0-9]+$ ]] || ctx_size=0
[[ "$term_width" =~ ^[0-9]+$ ]] || term_width=0
(( used_pct > 100 )) && used_pct=100

user=$(whoami)
host=$(hostname -s)

raw_dir="$dir"
[ -z "$raw_dir" ] && raw_dir=$(pwd)
dir="${raw_dir/#$HOME/\~}"

# Model display (avoid duplicating effort if already inside display_name)
if [ -n "$model" ] && [ -n "$effort" ] && [[ "$model" != *"($effort)"* ]]; then
  model_display="${model} (${effort})"
else
  model_display="${model}"
fi

# Conda env
conda_part=""
[ -n "$CONDA_DEFAULT_ENV" ] && conda_part="(${CONDA_DEFAULT_ENV})"

# Git branch fallback when payload omits .vcs.branch
if [ -z "$git_branch" ]; then
  if git -C "$raw_dir" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$raw_dir" branch --show-current 2>/dev/null)
  fi
fi
if [ -n "$git_branch" ] && [ "$is_dirty" = "true" ]; then
  git_branch="${git_branch}*"
fi

# Format token counts concisely (e.g. 850, 1.5k, 120k, 1M)
fmt_tok() {
  local n="${1:-0}"
  if (( n >= 1000000 )); then
    local tenths=$(( (n + 50000) / 100000 ))
    if (( tenths % 10 == 0 )); then
      printf '%dM' $(( tenths / 10 ))
    else
      printf '%d.%dM' $(( tenths / 10 )) $(( tenths % 10 ))
    fi
  elif (( n >= 10000 )); then
    printf '%dk' $(( (n + 500) / 1000 ))
  elif (( n >= 1000 )); then
    local tenths=$(( (n + 50) / 100 ))
    if (( tenths % 10 == 0 )); then
      printf '%dk' $(( tenths / 10 ))
    else
      printf '%d.%dk' $(( tenths / 10 )) $(( tenths % 10 ))
    fi
  else
    printf '%d' "$n"
  fi
}

# Shorten directory path when Line 1 would exceed terminal_width
shorten_dir() {
  local d="$1"
  local max_len="$2"
  if (( ${#d} <= max_len )) || (( max_len < 8 )); then
    printf '%s' "$d"
    return
  fi

  local prefix=""
  local rest="$d"
  if [[ "$rest" == "~/"* ]]; then
    prefix="~/"
    rest="${rest#\~/}"
  elif [[ "$rest" == "/"* ]]; then
    prefix="/"
    rest="${rest#/}"
  fi

  IFS='/' read -ra parts <<< "$rest"
  local n="${#parts[@]}"
  if (( n >= 2 )); then
    local two="${prefix}.../${parts[$((n-2))]}/${parts[$((n-1))]}"
    if (( ${#two} <= max_len )); then
      printf '%s' "$two"
      return
    fi
  fi
  if (( n >= 1 )); then
    local one="${prefix}.../${parts[$((n-1))]}"
    if (( ${#one} <= max_len )); then
      printf '%s' "$one"
      return
    fi
  fi

  local tail_len=$(( max_len - 3 ))
  printf '...%s' "${d: -$tail_len}"
}

# Compute fixed visible width of Line 1 segments (excluding dir)
line1_fixed=$(( ${#user} + 1 + ${#host} + 1 ))
[ -n "$conda_part" ] && line1_fixed=$(( line1_fixed + ${#conda_part} + 1 ))
[ -n "$git_branch" ] && line1_fixed=$(( line1_fixed + 5 + ${#git_branch} ))
[ -n "$model_display" ] && line1_fixed=$(( line1_fixed + 5 + ${#model_display} ))
[ -n "$plan_tier" ] && line1_fixed=$(( line1_fixed + 5 + ${#plan_tier} ))

if (( term_width > 0 )); then
  avail_dir=$(( term_width - line1_fixed ))
  (( avail_dir < 12 )) && avail_dir=12
  dir=$(shorten_dir "$dir" "$avail_dir")
fi

# Colors
ESC=$'\033'
WHITE="${ESC}[37m"
GREEN="${ESC}[32m"
BLUE="${ESC}[34m"
ORANGE="${ESC}[38;5;208m"
CYAN="${ESC}[36m"
RED="${ESC}[31m"
R="${ESC}[0m"

# Progress bar (10 cells). Both filled and empty cells are background-colored spaces:
# no glyphs at all, so they cannot misalign or overflow the line height. (Block/shade
# characters like ░ ▒ ▓ █ rendered taller than the line in some fonts and overlapped
# the line above.)
BAR_WIDTH=10
FILLED=$(( used_pct * BAR_WIDTH / 100 ))
EMPTY=$(( BAR_WIDTH - FILLED ))
if (( used_pct >= 80 )); then
  FILL_BG="${ESC}[48;5;203m"   # red warning
  PCT_COLOR="$RED"
else
  FILL_BG="${ESC}[48;5;114m"   # soft green
  PCT_COLOR=""
fi
EMPTY_BG="${ESC}[48;5;240m"    # dark gray
BAR=""
if (( FILLED > 0 )); then
  printf -v FILL "%${FILLED}s"
  BAR="${FILL_BG}${FILL}${R}"
fi
if (( EMPTY > 0 )); then
  printf -v PAD "%${EMPTY}s"
  BAR="${BAR}${EMPTY_BG}${PAD}${R}"
fi

# Context token details
ctx_detail="${used_pct}%"
if (( ctx_size > 0 )); then
  used_tok=$(( used_pct * ctx_size / 100 ))
  ctx_detail="${used_pct}% ($(fmt_tok "$used_tok")/$(fmt_tok "$ctx_size"))"
fi
[ -n "$PCT_COLOR" ] && ctx_detail="${PCT_COLOR}${ctx_detail}${R}"

# Reset countdown & cost
reset_part=""
if [[ "$reset_secs" =~ ^[0-9]+$ ]] && (( reset_secs > 0 )); then
  hrs=$(( reset_secs / 3600 ))
  mins=$(( (reset_secs % 3600) / 60 ))
  reset_part="Reset: ${hrs} hr ${mins} min"
fi

cost_part=""
if [ -n "$cost_val" ]; then
  cost_part=$(printf '$%.2f' "$cost_val" 2>/dev/null || true)
fi

# Line 1: (env)user@host:dir | ⎇ branch | [Model] | [Tier]
line1=""
[ -n "$conda_part" ] && line1="${WHITE}${conda_part}${R} "
line1="${line1}${GREEN}${user}@${host}${R}:${BLUE}${dir}${R}"
[ -n "$git_branch" ] && line1="${line1} | ⎇ ${git_branch}"
[ -n "$model_display" ] && line1="${line1} | ${ORANGE}[${model_display}]${R}"
[ -n "$plan_tier" ] && line1="${line1} | ${CYAN}[${plan_tier}]${R}"

# Line 2: visual progress bar + context tokens + gemini-5h/weekly + reset + cost
line2="${BAR} ${ctx_detail}"
[ -n "$primary_rate" ] && line2="${line2} | ${primary_rate}"
[ -n "$reset_part" ] && line2="${line2} | ${reset_part}"
[ -n "$cost_part" ] && line2="${line2} | ${cost_part}"

printf '%b\n' "$line1"
printf '%b\n' "$line2"
if [ -n "$other_rate" ]; then
  echo "$other_rate"
fi
