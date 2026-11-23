#!/usr/bin/env bash
set -euo pipefail

# Provision or tear down a disposable GCP Tailscale exit node VM.
# Defaults mirror the original Seoul (asia-northeast3-c) setup.

PROJECT="${GCP_PROJECT:-plucky-engine-436207-u4}"
ZONE="${GCP_ZONE:-asia-northeast3-c}"
VM_NAME="${GCP_VM_NAME:-tailscale-kr-exit}"
MACHINE_TYPE="${GCP_MACHINE_TYPE:-e2-micro}"
DISK_SIZE="${GCP_DISK_SIZE:-10GB}"
DISK_TYPE="${GCP_DISK_TYPE:-pd-balanced}"
IMAGE_FAMILY="${GCP_IMAGE_FAMILY:-debian-13}"
IMAGE_PROJECT="${GCP_IMAGE_PROJECT:-debian-cloud}"
AUTHKEY="${TAILSCALE_AUTHKEY:-}"
STARTUP_TMP=""
trap '[[ -n "$STARTUP_TMP" ]] && rm -f "$STARTUP_TMP"' EXIT

usage() {
    cat <<'EOF'
Usage:
  tailscale-exit-node.sh <command> [options]

Commands:
  up             Create a GCP VM with IP forwarding and Tailscale installed
  login          SSH into the VM and run `tailscale up --advertise-exit-node`
  down | delete  Delete the VM (and auto-delete its boot disk to stop all billing)
  start          Start an existing stopped VM
  stop           Stop a running VM (note: boot disk storage still bills while stopped)
  ssh            Open an interactive SSH session to the VM
  status         List instances, disks, and static addresses in the project

Options:
  --project ID         GCP project ID (default: plucky-engine-436207-u4)
  --zone ZONE          GCP zone (default: asia-northeast3-c)
  --name NAME          VM instance name (default: tailscale-kr-exit)
  --machine-type TYPE  GCE machine type (default: e2-micro)
  --authkey KEY        Tailscale auth key for unattended `tailscale up`
  -h, --help           Show this help

Environment overrides:
  GCP_PROJECT, GCP_ZONE, GCP_VM_NAME, GCP_MACHINE_TYPE,
  GCP_DISK_SIZE, GCP_DISK_TYPE, GCP_IMAGE_FAMILY, GCP_IMAGE_PROJECT,
  TAILSCALE_AUTHKEY
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

COMMAND="$1"
shift

if [[ "$COMMAND" == "-h" || "$COMMAND" == "--help" || "$COMMAND" == "help" ]]; then
    usage
    exit 0
fi

require_arg() {
    if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Error: $1 requires a value." >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            require_arg "$@"
            PROJECT="$2"
            shift 2
            ;;
        --zone)
            require_arg "$@"
            ZONE="$2"
            shift 2
            ;;
        --name)
            require_arg "$@"
            VM_NAME="$2"
            shift 2
            ;;
        --machine-type)
            require_arg "$@"
            MACHINE_TYPE="$2"
            shift 2
            ;;
        --authkey)
            require_arg "$@"
            AUTHKEY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_gcloud() {
    if ! command -v gcloud >/dev/null 2>&1; then
        echo "Error: gcloud CLI not found in PATH." >&2
        exit 1
    fi
}

cmd_up() {
    require_gcloud

    STARTUP_TMP="$(mktemp /tmp/tailscale-exit-startup.XXXXXX.sh)"
    local startup_file="$STARTUP_TMP"

    cat > "$startup_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Enable IPv4 and IPv6 forwarding required for a Tailscale exit node.
cat > /etc/sysctl.d/99-tailscale.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL
sysctl -p /etc/sysctl.d/99-tailscale.conf

if ! command -v tailscale >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# Best-effort UDP GRO forwarding optimization recommended by Tailscale.
NETDEV="$(ip -o route get 8.8.8.8 2>/dev/null | cut -f 5 -d ' ' || true)"
if [[ -n "$NETDEV" ]] && command -v ethtool >/dev/null 2>&1; then
    ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off || true
fi
EOF

    if [[ -n "$AUTHKEY" ]]; then
        printf '\ntailscale up --authkey=%q --advertise-exit-node --hostname=%q\n' \
            "$AUTHKEY" "$VM_NAME" >> "$startup_file"
    fi

    gcloud compute instances create "$VM_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --image-family="$IMAGE_FAMILY" \
        --image-project="$IMAGE_PROJECT" \
        --boot-disk-size="$DISK_SIZE" \
        --boot-disk-type="$DISK_TYPE" \
        --can-ip-forward \
        --metadata-from-file="startup-script=${startup_file}"

    cat <<EOF

VM created: ${VM_NAME} (${ZONE}, project=${PROJECT})
Next steps:
EOF
    if [[ -z "$AUTHKEY" ]]; then
        cat <<EOF
  1. Wait ~30s for startup-script to finish installing Tailscale, then run:
       $0 login --project ${PROJECT} --zone ${ZONE} --name ${VM_NAME}
  2. Approve "Use as exit node" in Tailscale Admin Console:
       https://login.tailscale.com/admin/machines
EOF
    else
        cat <<EOF
  1. Approve "Use as exit node" (if not auto-approved via ACL tag) in:
       https://login.tailscale.com/admin/machines
EOF
    fi
    cat <<EOF
  3. When finished, delete the VM so charges drop to \$0:
       $0 down --project ${PROJECT} --zone ${ZONE} --name ${VM_NAME}
EOF
}

cmd_login() {
    require_gcloud
    gcloud compute ssh "$VM_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --command="for i in \$(seq 1 30); do command -v tailscale >/dev/null 2>&1 && break; echo 'Waiting for tailscale install...'; sleep 3; done; sudo tailscale up --advertise-exit-node --hostname='${VM_NAME}'"
}

cmd_down() {
    require_gcloud
    gcloud compute instances delete "$VM_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --quiet
    echo "Deleted ${VM_NAME} (boot disk auto-deleted). Also remove offline node in Tailscale Admin if desired."
}

cmd_start() {
    require_gcloud
    gcloud compute instances start "$VM_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE"
}

cmd_stop() {
    require_gcloud
    gcloud compute instances stop "$VM_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE"
}

cmd_ssh() {
    require_gcloud
    gcloud compute ssh "$VM_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE"
}

cmd_status() {
    require_gcloud
    echo "=== Instances (${PROJECT}) ==="
    gcloud compute instances list --project="$PROJECT"
    echo "=== Disks (${PROJECT}) ==="
    gcloud compute disks list --project="$PROJECT"
    echo "=== Static Addresses (${PROJECT}) ==="
    gcloud compute addresses list --project="$PROJECT"
}

case "$COMMAND" in
    up)
        cmd_up
        ;;
    login)
        cmd_login
        ;;
    down|delete)
        cmd_down
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    ssh)
        cmd_ssh
        ;;
    status)
        cmd_status
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        usage >&2
        exit 1
        ;;
esac
