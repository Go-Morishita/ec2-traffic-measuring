# EC2 HTTP Traffic Lab

A fleet of Python HTTP app servers sits behind an NGINX load balancer on a
single EC2 instance. The point of the lab is to push traffic through it and
measure what the instance does — and to make the number of app servers a single
variable, so an autoscaling policy can drive it.

```text
Mac (curl / hey) → EC2:8080 → nginx:8080 → app1..appN:8000
Mac (ansible)    → EC2:22   → SSH jump   → 127.0.0.1:222N → container:22
```

The app containers' SSH ports are bound to the EC2 host's loopback interface,
so Ansible reaches them by jumping through the EC2 host. The security group
only opens `22` and `8080`, and the container SSH key never leaves your Mac.

## Division of responsibility

| Layer | Tool | Where | When it runs |
| --- | --- | --- | --- |
| VPC, subnet, security group, instance | Terraform | `ec2/terraform/` | When the instance changes |
| Docker engine, Compose plugin | Shell | `scripts/bootstrap_ec2.sh` | Once per instance |
| Containers, NGINX, application | Ansible | `ansible/` | Every time you change the fleet |

Terraform creates a plain, empty instance and stops there — it has no
`user_data`. The shell script does the one-shot host setup that gains nothing
from being idempotent. Everything that you re-run while experimenting belongs
to Ansible.

## Files

```
ansible.cfg                                  Ansible settings (must sit at the repo root)
ansible/
├── ec2.yaml                                 the only playbook you run
├── inventory.yaml                           connection details + all the knobs
├── ansible_container_key(.pub)              key pair for reaching the containers
└── roles/
    ├── container_fleet/                     builds the fleet on the EC2 host
    │   ├── tasks/main.yaml
    │   ├── handlers/main.yaml                 reloads NGINX when its config changes
    │   └── templates/
    │       ├── docker-compose.yaml.j2         rendered from app_count
    │       └── app.conf.j2                    rendered from app_count
    └── app_server/tasks/main.yaml           configures one app server
app/main.py                                  the HTTP server being measured
docker/Dockerfile.virtual-server             container image: sshd as PID 1
scripts/bootstrap_ec2.sh                     one-time host setup
ec2/terraform/                               the instance and its network
```

`ansible.cfg` lives at the repository root on purpose: Ansible looks for it in
the current working directory, not next to the playbook.

## Setup

### 1. Provision the instance

```bash
terraform -chdir=ec2/terraform apply
```

The SSH key at `ssh_public_key_path` has no passphrase, so neither Terraform
nor Ansible needs `ssh-agent`. Terraform registers the public half with EC2 and
the instance accepts it on first boot.

### 2. Point your shell at the instance

```bash
export EC2_HOST=$(terraform -chdir=ec2/terraform output -raw public_ip)
```

Every later step reads `EC2_HOST`, so keep this shell or re-export it. The
playbook asserts it is non-empty before doing anything else.

Confirm you can reach the host:

```bash
ssh -i ~/.ssh/ec2-traffic-measuring -o StrictHostKeyChecking=accept-new ec2-user@$EC2_HOST 'uname -m'
```

### 3. Bootstrap the host — once per instance

```bash
./scripts/bootstrap_ec2.sh
```

Installs the Docker engine, enables the service, adds `ec2-user` to the
`docker` group, and fetches the Compose plugin (Amazon Linux 2023 ships the
engine but not the plugin). It prints the two versions when it finishes, and it
is safe to re-run.

### 4. Build the fleet

```bash
ansible-playbook -i ansible/inventory.yaml ansible/ec2.yaml
```

A successful run ends with every app server appearing in the NGINX rotation, so
it doubles as an end-to-end verification.

> Do not use `--check`. Check mode skips the `command` tasks, so no containers
> are created and `wait_for` then fails on ports that will never open.

## How the playbook runs

`ansible/ec2.yaml` is three plays. The order matters, because play 2 cannot run
until play 1 has created its hosts.

**Play 1 — `Provision the container fleet`** (target: the EC2 host)

1. Assert `EC2_HOST` is set — delegated to `localhost`, since with no address
   there is nowhere to connect
2. Create `/opt/traffic-lab/{app,ansible,docker,docker/nginx-conf.d}`
3. Copy the image build context, mirroring the repository layout
4. Render `docker-compose.yaml` and `nginx-conf.d/app.conf` from `app_count`
5. Build the image once and share it across every app service
6. `docker compose up -d --remove-orphans`
7. Wait for each container's SSH port
8. `add_host` registers `app1..appN` into the `virtual_servers` group
9. *(handler)* reload NGINX if its config changed

**Play 2 — `Configure the virtual servers`** (target: `app1..appN`)

Copies `app/main.py` into each container and starts it. There is no loop here:
a play runs its task list once per target host, and play 1's `add_host` decided
how many hosts there are. Each host renders `SERVER_NAME={{ inventory_hostname }}`
to its own name, which is what the `X-Served-By` header reports.

**Play 3 — `Verify the load balancer`** (target: the EC2 host)

Sends `app_count × 3` requests through NGINX, tallies `X-Served-By`, and fails
if any app server never served one.

The image build runs once rather than once per service: `t4g.nano` has 0.5 GB
of RAM and no swap, so parallel per-service builds risk an OOM.

## Changing the number of app servers

`app_count` in `ansible/inventory.yaml` is the single knob. Override it per run:

```bash
ansible-playbook -i ansible/inventory.yaml ansible/ec2.yaml -e app_count=5
```

It drives the Compose services, the NGINX upstream list, the SSH port
assignments, the host registrations, and the verification threshold. Scaling up
only creates the new containers; scaling back down removes the extras via
`--remove-orphans`.

This is the variable the ML autoscaling experiment is meant to optimise: too
many containers waste the instance, too few cannot absorb the traffic.

Two things to know before scaling far:

- Ansible's default `forks` is 5, so play 2 serialises into batches beyond five
  app servers. Raise it in `ansible.cfg` if you go higher.
- `t4g.nano` has 0.5 GB of RAM. If the build or the containers run out, set
  `instance_type = "t4g.small"` in `ec2/terraform/terraform.tfvars` and re-apply.

## Send traffic and read the metrics

```bash
curl -i "http://$EC2_HOST:8080/"
```

```bash
for i in $(seq 1 15); do curl -sS -o /dev/null -D - http://$EC2_HOST:8080/ | awk 'tolower($1)=="x-served-by:"{print $2}'; done | tr -d '\r' | sort | uniq -c
```

```bash
curl -sS -o /dev/null -w 'time=%{time_total}s down=%{speed_download}B/s\n' "http://$EC2_HOST:8080/download?mb=10"
hey -z 60s -c 20 "http://$EC2_HOST:8080/download?mb=1"
```

A `POST` to any path returns `X-Received-MB` and `X-Receive-MBps` alongside
`X-Served-By`:

```bash
curl -sS -X POST --data-binary @payloads/payload_1mb.bin -D - -o /dev/null "http://$EC2_HOST:8080/" | grep -i '^x-'
```

Then read `NetworkIn`, `NetworkOut`, `NetworkPacketsIn`, `NetworkPacketsOut`,
`CPUUtilization`, and `CPUCreditBalance` under CloudWatch → EC2 → Per-Instance
Metrics.

## Troubleshooting

**Everything hangs.** The security group only admits `my_ip_cidr`, and home IPs
change:

```bash
curl -s https://checkip.amazonaws.com   # update my_ip_cidr in terraform.tfvars
terraform -chdir=ec2/terraform apply    # updates the security group in place
```

**Play 2 cannot connect.** Test the jump through the EC2 host directly:

```bash
ssh -i ansible/ansible_container_key -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/ec2-traffic-measuring ec2-user@$EC2_HOST" -p 2221 ansible@127.0.0.1 'hostname'
```

**Inspect the running fleet:**

```bash
ssh -i ~/.ssh/ec2-traffic-measuring ec2-user@$EC2_HOST 'docker ps; docker logs traffic-nginx --tail 20'
```

**NGINX serving a stale config.** The rendered config is mounted as a
*directory* (`./nginx-conf.d:/etc/nginx/conf.d:ro`), not a single file. Docker
binds a single-file mount by inode, and Ansible's `template` module replaces
files atomically via `rename()` — so a file mount would keep pointing at the old
inode and silently ignore every config change. If you ever change that volume
back to a file mount, config updates will stop taking effect.
