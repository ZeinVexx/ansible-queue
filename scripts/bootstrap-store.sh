#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root"
  exit 1
fi

if [ $# -lt 3 ]; then
  echo "Usage: $0 <repo_url> <repo_branch> <store_id>"
  echo "Example: $0 https://github.com/acme/queue-ansible.git main store-001"
  exit 1
fi

REPO_URL="$1"
REPO_BRANCH="$2"
STORE_ID="$3"

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ansible git curl docker.io python3-pip
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y ansible git curl docker python3-pip
elif command -v yum >/dev/null 2>&1; then
  yum install -y epel-release
  yum install -y ansible git curl docker python3-pip
else
  echo "Unsupported package manager"
  exit 1
fi

systemctl enable --now docker

# Install required collections from this repo so the first pull run can apply roles.
ansible-galaxy collection install -r collections/requirements.yml

mkdir -p /opt/ansible-pull/queue
mkdir -p /etc/default

cat >/etc/default/ansible-pull-queue <<EOF
REPO_URL=${REPO_URL}
REPO_BRANCH=${REPO_BRANCH}
STORE_ID=${STORE_ID}
EOF

install -m 0644 systemd/ansible-pull-queue.service /etc/systemd/system/ansible-pull-queue.service
install -m 0644 systemd/ansible-pull-queue.timer /etc/systemd/system/ansible-pull-queue.timer

systemctl daemon-reload
systemctl enable --now ansible-pull-queue.timer
systemctl start ansible-pull-queue.service

echo "Bootstrap complete for ${STORE_ID}"
