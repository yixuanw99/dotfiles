# GCP Tailscale Exit Node

Disposable GCP VM helper (`tailscale-exit-node.sh`) for spinning up an on-demand Tailscale exit node (default: Seoul, `asia-northeast3-c`) and deleting it cleanly afterward so ongoing charges stay at `$0`.

## Quick Start

1. **Create the VM** (enables `--can-ip-forward`, configures `ip_forward = 1`, and installs Tailscale via `startup-script`):

   ```sh
   ~/repos/dotfiles/gcp/tailscale-exit-node.sh up
   ```

2. **Authenticate Tailscale & advertise as exit node** (wait ~30 seconds after creation):

   ```sh
   ~/repos/dotfiles/gcp/tailscale-exit-node.sh login
   ```

   Open the printed Tailscale login URL, then enable **Use as exit node** for the machine in the [Tailscale Admin Console](https://login.tailscale.com/admin/machines).

3. **Delete when finished** (removes the VM and its auto-deleted boot disk; `$0` ongoing cost):

   ```sh
   ~/repos/dotfiles/gcp/tailscale-exit-node.sh down
   ```

## Common Variations

- **Other region** (e.g. Tokyo `asia-northeast1-b` or Singapore `asia-southeast1-b`):

  ```sh
  ~/repos/dotfiles/gcp/tailscale-exit-node.sh up --zone asia-northeast1-b --name tailscale-jp-exit
  ~/repos/dotfiles/gcp/tailscale-exit-node.sh login --zone asia-northeast1-b --name tailscale-jp-exit
  ~/repos/dotfiles/gcp/tailscale-exit-node.sh down --zone asia-northeast1-b --name tailscale-jp-exit
  ```

- **Unattended login with a Tailscale Auth Key**:

  ```sh
  TAILSCALE_AUTHKEY="tskey-auth-..." ~/repos/dotfiles/gcp/tailscale-exit-node.sh up
  ```

- **Check remaining VMs / disks / static IPs**:

  ```sh
  ~/repos/dotfiles/gcp/tailscale-exit-node.sh status
  ```

## Notes

- **Cost**: Stopping (`stop`) a VM stops compute charges, but `pd-balanced` boot disk storage still bills while the disk exists. Use `down` when you want zero ongoing cost.
- **No static IP**: The script uses an ephemeral external IP (no static IP reservation charges) and default VPC firewall rules (no extra inbound ports required for Tailscale).
