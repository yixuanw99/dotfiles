#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="${HOME}/.bashrc"
CLAUDE_DIR="${HOME}/.claude"
AGY_DIR="${HOME}/.gemini/antigravity-cli"
LOCAL_BIN="${HOME}/.local/bin"

mkdir -p "$CLAUDE_DIR" "$AGY_DIR" "$LOCAL_BIN"
touch "$BASHRC"

ln -sfn "${DOTFILES_DIR}/.hc_wrapper.sh" "${HOME}/.hc_wrapper.sh"
ln -sfn "${DOTFILES_DIR}/claude/statusline-command.sh" "${CLAUDE_DIR}/statusline-command.sh"
ln -sfn "${DOTFILES_DIR}/agy/antigravity-statusline.sh" "${LOCAL_BIN}/antigravity-statusline.sh"

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

merge_statusline_json() {
    local target="$1"
    local jq_expr="$2"
    [ -f "$target" ] || printf '{}\n' > "$target"
    local tmp_file
    tmp_file="$(mktemp "${target}.tmp.XXXXXX")"
    jq "$jq_expr" "$target" > "$tmp_file"
    mv "$tmp_file" "$target"
}

# Merge statusLine settings without clobbering existing keys in each file.
if command -v jq >/dev/null 2>&1; then
    merge_statusline_json \
        "${CLAUDE_DIR}/settings.json" \
        '.statusLine = {"type": "command", "command": "bash \"$HOME/.claude/statusline-command.sh\""}'
    merge_statusline_json \
        "${AGY_DIR}/settings.json" \
        '.statusLine = {"type": "command", "command": (env.HOME + "/.local/bin/antigravity-statusline.sh"), "enabled": true}'
else
    echo "Warning: jq not found; install jq for statusLine scripts and configure settings.json manually." >&2
fi

echo "Installed dotfiles from $DOTFILES_DIR"
echo "Run 'source ~/.bashrc' in existing shells to load updates."
