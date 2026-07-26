#!/usr/bin/env bash
# One-time setup of a fresh EC2 instance. Everything after this is done by
# ansible/ec2.yaml.
#
#   export EC2_HOST=$(terraform -chdir=ec2/terraform output -raw public_ip)
#   ./scripts/bootstrap_ec2.sh

set -euo pipefail

COMPOSE_VERSION="${COMPOSE_VERSION:-2.29.7}"
EC2_USER="${EC2_USER:-ec2-user}"
EC2_KEY="${EC2_KEY:-$HOME/.ssh/ec2-traffic-measuring}"

: "${EC2_HOST:?EC2_HOST is empty. Run: export EC2_HOST=\$(terraform -chdir=ec2/terraform output -raw public_ip)}"

ssh -i "$EC2_KEY" -o StrictHostKeyChecking=accept-new "${EC2_USER}@${EC2_HOST}" "EC2_USER=${EC2_USER} COMPOSE_VERSION=${COMPOSE_VERSION} bash -s" <<'REMOTE'
set -euo pipefail

sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker "$EC2_USER"

# Amazon Linux 2023 ships the Docker engine but not the Compose plugin.
sudo mkdir -p /usr/libexec/docker/cli-plugins
sudo curl -fsSL -o /usr/libexec/docker/cli-plugins/docker-compose "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)"
sudo chmod 0755 /usr/libexec/docker/cli-plugins/docker-compose

docker --version
docker compose version
REMOTE
