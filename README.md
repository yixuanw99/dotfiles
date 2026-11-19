# dotfiles

Personal shell, Claude Code, and Antigravity CLI (`agy`) utilities:

- `.hc_wrapper.sh`: Interactive `hc` (`herdr-core`) bash wrapper adding screen-style `hc -S`, `hc -ls` / `hc ls` (with task info), and `hc -r`.
- `claude/statusline-command.sh`: Two-line Claude Code status line (`conda`, `user@host:dir`, git branch, model, context usage bar, 5h/7d rate limits). Requires `jq`.
- `agy/antigravity-statusline.sh`: Two-line Antigravity CLI (`agy`) status line (workspace, model/effort, plan tier, VCS dirty/branch, quota/reset/cost, plus Claude fallback). Requires `jq`.
- `install.sh`: Symlinks the scripts into `$HOME`, configures immediate `history -a` + `.hc_wrapper.sh` in `~/.bashrc`, and merges `statusLine` into `~/.claude/settings.json` and `~/.gemini/antigravity-cli/settings.json`.

## Quick Install

```sh
git clone https://github.com/yixuanw99/dotfiles.git ~/repos/dotfiles
bash ~/repos/dotfiles/install.sh
source ~/.bashrc
```
