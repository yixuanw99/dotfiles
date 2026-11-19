#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="${HOME}/.bashrc"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

mkdir -p "$CLAUDE_DIR"
touch "$BASHRC"

ln -sfn "${DOTFILES_DIR}/.hc_wrapper.sh" "${HOME}/.hc_wrapper.sh"
ln -sfn "${DOTFILES_DIR}/claude/statusline-command.sh" "${CLAUDE_DIR}/statusline-command.sh"

# Ensure immediate bash history flush (survives OOM / SIGKILL) and hc wrapper loading.
if ! grep -Fq 'history -a' "$BASHRC"; then
    cat >> "$BASHRC" <<'EOF'

# Flush history to disk after each command so OOM/SIGKILL won't lose it
shopt -s histappend
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF
fi

if ! grep -Fq '.hc_wrapper.sh' "$BASHRC"; then
    cat >> "$BASHRC" <<'EOF'

# Interactive hc wrapper (-S, -ls, -r)
[ -f "$HOME/.hc_wrapper.sh" ] && . "$HOME/.hc_wrapper.sh"
EOF
fi

# Merge portable statusLine setting into ~/.claude/settings.json without clobbering existing keys.
if command -v jq >/dev/null 2>&1; then
    if [ ! -f "$SETTINGS_FILE" ]; then
        printf '{}\n' > "$SETTINGS_FILE"
    fi
    tmp_file="$(mktemp "${SETTINGS_FILE}.tmp.XXXXXX")"
    jq '.statusLine = {"type": "command", "command": "bash \"$HOME/.claude/statusline-command.sh\""}' \
        "$SETTINGS_FILE" > "$tmp_file"
    mv "$tmp_file" "$SETTINGS_FILE"
else
    echo "Warning: jq not found; install jq for Claude statusLine and set statusLine manually in $SETTINGS_FILE" >&2
fi

echo "Installed dotfiles from $DOTFILES_DIR"
echo "Run 'source ~/.bashrc' in existing shells to load updates."
