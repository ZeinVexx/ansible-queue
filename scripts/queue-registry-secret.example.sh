#!/usr/bin/env bash
set -euo pipefail

# Example helper for queue_registry_auth.secret_fetch_command.
# It must print JSON to stdout: {"username":"...","password":"..."}
#
# Copy to /usr/local/bin/queue-registry-secret and customize one backend below.

BACKEND="${1:-aws}"

case "$BACKEND" in
  aws)
    # Requires AWS identity on VM and secret value as JSON string.
    aws secretsmanager get-secret-value \
      --secret-id queue/docker \
      --query SecretString \
      --output text
    ;;
  azure)
    # Requires Azure login/managed identity and secret value as JSON string.
    az keyvault secret show \
      --vault-name my-vault \
      --name queue-docker \
      --query value \
      -o tsv
    ;;
  gcp)
    # Requires service account identity and secret value as JSON string.
    gcloud secrets versions access latest \
      --secret=queue-docker
    ;;
  vault)
    # Requires Vault auth and kv secret fields username/password.
    vault kv get -format=json secret/queue/docker | jq -c '.data.data'
    ;;
  *)
    echo "Unsupported backend: $BACKEND" >&2
    exit 1
    ;;
esac
