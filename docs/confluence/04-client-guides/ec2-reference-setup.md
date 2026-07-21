---
title: Reference EC2 environment & setup
labels: [byoc, client, reference, ec2]
---

> Source: generated from `docs/confluence/04-client-guides/ec2-reference-setup.md`. Edit in git, not in Confluence.

# Reference EC2 environment & setup

This is the environment we run Daytona on and the exact steps to stand it up. Provision
an EC2 host that **matches or exceeds** the spec below, then follow the setup steps. It
ends at the same [acceptance test](../06-verify-operate/acceptance-test) (boot + a working
sandbox).

> ⚠ **Architecture: x86_64 / amd64 only.** The Daytona server images are single-arch
> (amd64). They will **not** run on Graviton/arm64 instances (`t4g`, `m6g`, `c7g`, …).
> Choose an Intel/AMD instance family.

## 1. Infrastructure spec

| Item | Value | Notes |
|---|---|---|
| **Region** | `us-east-1` | Our registry lives here. A different region works; if pulling from our ECR, cross-region adds latency + egress cost. |
| **AMI** | Ubuntu Server 24.04 LTS (x86_64) | AMI IDs are region- and date-specific — **resolve the current one via SSM** (below), don't hard-code. Amazon Linux 2023 also works; steps below assume Ubuntu. |
| **Instance type** | **min** `m5.xlarge` (4 vCPU / 16 GB) · **recommended** `m5.2xlarge` (8 vCPU / 32 GB) | The api reserves a default runner of **4 vCPU / 8 GB** for sandboxes; the control-plane services need the rest. Size up for concurrent sandboxes. x86_64 only. |
| **Root EBS** | `gp3`, **100 GB** min | Holds the OS + ~10 GB of images + logs. gp3 3000 IOPS / 125 MB/s baseline is fine. |
| **Data EBS (recommended)** | `gp3`, **200 GB**, mounted at `/var/lib/docker` | Sandbox image layers + the runner's Docker-in-Docker grow here. Optional but strongly recommended for real workloads. |
| **Security group — inbound** | `22` (SSH, your IP only), `3002`, `4003`, `5556`, `2222` | 3002 api/dashboard · 4003 proxy · 5556 dex · 2222 ssh-gateway. Everything else binds to 127.0.0.1. |
| **Security group — outbound** | `443` to the image registry (connected path) **or** none (offline bundle) | Air-gapped hosts need no outbound access at deploy. |
| **IAM instance role** | ECR read (connected path only) | Only needed if the host pulls images from a registry. The offline-bundle path needs **no** IAM. The runner uses the **in-stack MinIO** for sandbox storage — no AWS S3 IAM required. |

### Resolve the current Ubuntu 24.04 AMI ID (per region)
```bash
aws ssm get-parameter --region us-east-1 \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query Parameter.Value --output text
```

### Capture the exact spec of a running reference host
To copy the exact values from an already-running instance (e.g. to pin what we ran), run
on that box:
```bash
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
H="X-aws-ec2-metadata-token: $TOKEN"
echo "ami-id:        $(curl -s -H "$H" http://169.254.169.254/latest/meta-data/ami-id)"
echo "instance-type: $(curl -s -H "$H" http://169.254.169.254/latest/meta-data/instance-type)"
echo "region:        $(curl -s -H "$H" http://169.254.169.254/latest/meta-data/placement/region)"
lsblk                                  # EBS volumes + sizes
```

## 2. Launch the EC2

**Console:** EC2 → Launch instance →
- **AMI:** Ubuntu Server 24.04 LTS (x86_64) — the ID from the SSM lookup.
- **Instance type:** `m5.2xlarge` (or `m5.xlarge` minimum).
- **Key pair:** your SSH key.
- **Storage:** root gp3 100 GB; (recommended) add a second gp3 200 GB volume.
- **Security group:** inbound 22 (your IP), 3002, 4003, 5556, 2222.
- **IAM role:** attach an ECR-read role only if pulling from a registry.

**CLI equivalent** (fill the placeholders):
```bash
AMI=$(aws ssm get-parameter --region us-east-1 \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query Parameter.Value --output text)
aws ec2 run-instances --region us-east-1 \
  --image-id "$AMI" --instance-type m5.2xlarge \
  --key-name <your-key> --security-group-ids <sg-id> --subnet-id <subnet-id> \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
  --iam-instance-profile Name=<ecr-read-profile>   # omit for the offline-bundle path
```

## 3. Bootstrap the host (Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"      # then log out/in so docker works without sudo

# mount-s3: the runner bind-mounts /usr/bin/mount-s3 — without it the runner
# silently misbehaves.
wget -q https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb
sudo apt-get install -y ./mount-s3.deb
ls -l /usr/bin/mount-s3 /dev/fuse    # both must exist
```

### (Recommended) put Docker's data on the second volume
```bash
# assuming the extra volume is /dev/nvme1n1 (check with lsblk):
sudo mkfs.ext4 /dev/nvme1n1
sudo systemctl stop docker
sudo mkdir -p /var/lib/docker && echo '/dev/nvme1n1 /var/lib/docker ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
sudo mount -a && sudo systemctl start docker
```

## 4. Deploy Daytona

Get the delivery artifacts onto the host and bring the stack up. Follow the guide for the
image-source path you were given:

- **Offline bundle** (no registry access): [Air-gapped — offline bundle](airgapped-offline-bundle)
- **Pull all images from the vendor registry:** [Connected — all from vendor registry](connected-all-from-registry)
- **Your own internal registry:** [Air-gapped / fleet — internal registry](airgapped-internal-registry)

Each generates the config, all secrets, and brings the stack up with one installer.

## 5. Verify

Run the [acceptance test](../06-verify-operate/acceptance-test): all services up,
`curl http://<host>:3002/api/health` → `200`, then create a sandbox. A successful
create + exec proves the privileged runner, proxy, and ssh-gateway work on this host —
the real signal that the environment is correctly sized and configured.

## Sizing notes (why these numbers)

- The api provisions a **default runner at 4 vCPU / 8 GB** (`DEFAULT_RUNNER_CPU=4`,
  `DEFAULT_RUNNER_MEMORY=8`). That capacity is reserved for sandboxes, so the host needs
  meaningful headroom above it — hence 16 GB minimum, 32 GB recommended.
- The **runner is privileged Docker-in-Docker**: it runs an inner dockerd that pulls and
  runs sandbox images. Those layers live under `/var/lib/docker` — the reason for the
  second EBS volume.
- **No nested virtualization** is required (DinD shares the host kernel), so standard
  `m5`/`m6i`/`c5` x86_64 instances are fine — just not Graviton.
