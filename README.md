# dotfiles

Personal shell and Claude Code utilities:

- `.hc_wrapper.sh`: Interactive `hc` (`herdr-core`) bash wrapper adding screen-style `hc -S`, `hc -ls` / `hc ls` (with task info), and `hc -r`.
- `claude/statusline-command.sh`: Two-line Claude Code status line (`conda`, `user@host:dir`, git branch, model, context usage bar, 5h/7d rate limits). Requires `jq`.
- `install.sh`: Symlinks the scripts into `$HOME`, configures immediate `history -a` + `.hc_wrapper.sh` in `~/.bashrc`, and merges `statusLine` into `~/.claude/settings.json`.

## Quick Install

```sh
git clone https://github.com/yixuanw99/dotfiles.git ~/repos/dotfiles
bash ~/repos/dotfiles/install.sh
source ~/.bashrc
```
