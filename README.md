# Queue Platform Operations with Ansible Pull (No SSH)

This repository is built for many small supermarket servers where each server runs a single queue container and updates itself using Ansible Pull.

## Why this pattern

- No SSH fan-out from a control node.
- Every store polls Git and applies only its own desired state.
- You can canary selected stores first, then expand rollout.
- You can run targeted operational commands and collect logs/status.

## Repository structure

- `playbooks/site.yml`: Main playbook executed by ansible-pull on each store.
- `rollout/targets.yml`: Controls image channels, canary stores, and per-store hard pins.
- `vars/stores/*.yml`: Per-store environment and queue category settings.
- `ops/commands.yml`: Targeted remote commands (executed locally at each store on pull).
- `roles/queue_container`: Deploys/updates the queue container.
- `roles/store_ops`: Handles command execution, log capture, and status publication.
- `systemd/*.service|*.timer`: Local scheduler for ansible-pull.
- `scripts/bootstrap-store.sh`: One-time bootstrap per store server.

## Bootstrap on each store server

Run once on each server:

```bash
cd /path/to/this/repo
sudo bash scripts/bootstrap-store.sh <repo_url> <branch> <store_id>
```

Example:

```bash
sudo bash scripts/bootstrap-store.sh https://github.com/acme/queue-ansible.git main store-001
```

This installs dependencies, enables Docker, and schedules pull runs every 2 minutes.

## Update strategy (isolate stores)

1. Set canary image in `rollout/targets.yml` under `channels.canary`.
2. Add selected stores to `store_channels` with `canary`.
3. Observe status/logs from canary stores.
4. Move more stores to canary or promote canary image to `channels.stable`.

For strict version exceptions, use `store_pins`.

## Sending commands to specific stores

Add command entries in `ops/commands.yml` with:

- `target_stores: ["store-001"]` for one store
- `target_stores: ["all"]` for all stores
- `enabled: true` to execute
- `once: true` to run only once per store
- `runner: host` for host-side checks like `systemctl`, `journalctl`, `df`, or `cat`
- `runner: container` for commands executed inside the queue container
- `become: true` when the host-side command needs root privileges
- `chdir: /path/to/dir` to run a host-side command in a specific directory

Results are stored locally in:

- `/var/lib/queue-agent/ops-history/*.json`

This is not an interactive shell. Ansible can run ad-hoc commands, but in this no-SSH design you queue the command in Git and the store applies it on the next pull cycle. That is the tradeoff for avoiding SSH.

## Light demo: run on multiple VMs

This repo is already set up to run a tiny public container demo across several VMs.

- Public image: `nginx:1.27.5-alpine` (stable)
- Canary image: `nginx:1.28.0-alpine`
- Container will be exposed on port 8080 of each VM
- Each VM gets a custom HTML page showing its store ID and channel

### Steps

1. Git push this repo to a reachable remote.
2. On VM 1:

```bash
sudo bash scripts/bootstrap-store.sh https://github.com/your-org/queue-demo.git main store-001
```

3. On VM 2:

```bash
sudo bash scripts/bootstrap-store.sh https://github.com/your-org/queue-demo.git main store-017
```

4. Wait 1-2 minutes.
5. Test each VM:

```bash
curl http://<vm-ip>:8080
```

Expected result: a small HTML page with the VM store ID and the current image tag.

To test a rollout, change `store_channels` in [rollout/targets.yml](rollout/targets.yml), commit, push, and wait for the next pull cycle.

## Logs and status

Each pull run writes:

- Latest logs: `/var/lib/queue-agent/status/latest-container.log`
- Status json: `/var/lib/queue-agent/status/status.json`

If `queue_status_webhook_url` is configured in `group_vars/all.yml`, status is POSTed to your API.

## Private Docker Registry with Secret Manager

The playbook can login to a private registry before image pull by fetching credentials
from a local secret manager command on each store VM.

Configure in `group_vars/all.yml`:

```yaml
queue_registry_auth:
	enabled: true
	registry_url: ghcr.io
	secret_fetch_command: "/usr/local/bin/queue-registry-secret"
	login_reauthorize: true
```

The command must print JSON to stdout:

```json
{"username":"my-user","password":"my-password-or-token"}
```

Suggested provider commands (examples):

- AWS Secrets Manager:
	`aws secretsmanager get-secret-value --secret-id queue/docker --query SecretString --output text`
- Azure Key Vault (if storing one JSON secret):
	`az keyvault secret show --vault-name my-vault --name queue-docker --query value -o tsv`
- GCP Secret Manager:
	`gcloud secrets versions access latest --secret=queue-docker`
- HashiCorp Vault:
	`vault kv get -format=json secret/queue/docker | jq -c '.data.data'`

Use IAM/managed identity/service account or vault auth on each VM so no static secret is committed to Git.

Quick validation on a store VM:

```bash
sudo -u root /usr/local/bin/queue-registry-secret
sudo systemctl start ansible-pull-queue.service
sudo journalctl -u ansible-pull-queue.service -n 100 --no-pager
```

## Notes

- This design assumes store nodes can reach your Git repository.
- Use HTTPS deploy tokens or another non-interactive credential strategy for private repos.
- Install required collection on store nodes:

```bash
ansible-galaxy collection install -r collections/requirements.yml
```
