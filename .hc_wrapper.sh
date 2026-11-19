# Interactive shell wrapper for hc: adds screen-like -S, -ls, -r
# while keeping native hc behavior intact for everything else.

hc() {
    case "${1:-}" in
        -S)
            if [ -n "${HC_TERMINAL_ID:-}" ]; then
                printf 'hc -S: already inside hc (%s); refused to avoid nested/orphan shells.\n' "$HC_TERMINAL_ID" >&2
                return 1
            fi
            shift
            if [ $# -eq 0 ] || [ -z "${1:-}" ] || [[ "$1" == -* ]]; then
                printf 'usage: hc -S <name> [command...]\n' >&2
                return 2
            fi
            local name="$1"
            shift
            command hc run --bg --keep --no-parent --name "$name" "$@" &&
                command hc attach --history 500 "$name"
            ;;
        -r)
            shift
            if [ $# -eq 0 ]; then
                command hc
            else
                command hc attach --history 500 "$@"
            fi
            ;;
        -ls|ls)
            local sub="$1"
            shift
            local use_enhanced=1
            local show_all=0
            local arg
            for arg in "$@"; do
                case "$arg" in
                    -a|--all) show_all=1 ;;
                    --json|--label|-h|--help) use_enhanced=0 ;;
                    *) use_enhanced=0 ;;
                esac
            done
            if [ "$use_enhanced" -eq 1 ] && [ -t 1 ]; then
                _hc_ls_enhanced "$show_all"
            else
                command hc ls "$@"
            fi
            ;;
        *)
            command hc "$@"
            ;;
    esac
}

_hc_ls_enhanced() {
    local show_all="${1:-0}"
    HC_WRAPPER_ALL="$show_all" python3 - <<'PY'
import json
import os
import subprocess

cmd = ["hc", "ls", "--json"]
if os.environ.get("HC_WRAPPER_ALL") == "1":
    cmd.append("--all")

ls_data = json.loads(subprocess.check_output(cmd))
terminals = ls_data.get("terminals", [])

rows = []
for t in terminals:
    addr = t["address"]
    try:
        g = json.loads(subprocess.check_output(["hc", "get", addr, "--json"]))
    except subprocess.CalledProcessError:
        g = {}
    st = g.get("status") or {}
    fg = g.get("foreground") or {}
    name = g.get("name") or "-"
    agent = t.get("agent") or fg.get("name") or "-"
    where = t.get("where") or "-"
    if t.get("state") == "live":
        status = st.get("state") or "running"
        dot = "●" if st.get("state") in ("working", "done", "idle", "blocked", "error") else "○"
    else:
        dot = "○"
        if g.get("signal") is not None:
            status = f"signal {g['signal']}"
        elif g.get("exit_code") is not None:
            status = f"exit {g['exit_code']}"
        else:
            status = t.get("state") or "finished"
    task = st.get("msg") or g.get("title") or " ".join(fg.get("argv", []))
    if len(task) > 72:
        task = task[:69] + "..."
    rows.append((f"{dot} {addr}", name, agent, where, status, task))

if rows:
    headers = ("ID", "NAME", "AGENT", "WHERE", "STATUS", "TASK")
    widths = [
        max(len(h), *(len(r[i]) for r in rows))
        for i, h in enumerate(headers)
    ]
    fmt = "  ".join(f"{{:{w}}}" for w in widths[:-1]) + "  {}"
    print(fmt.format(*headers))
    for r in rows:
        print(fmt.format(*r))

hidden = ls_data.get("hidden_finished", 0)
if hidden and os.environ.get("HC_WRAPPER_ALL") != "1":
    print(f"{hidden} finished hidden (-a)")
PY
}
