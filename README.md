# Floci Lab

A local AWS environment for learning and simulating infrastructure. It runs the
[Floci](https://floci.io) emulator, the Floci UI web console, and OpenTofu — all
on your machine, with no AWS account and no cost.

- **Emulator** — `http://localhost:4566`
- **Web console** — `http://localhost:4500`
- **Console API** — `http://localhost:4501`

---

## Table of contents

- [What this is](#what-this-is)
- [Requirements](#requirements)
- [Layout](#layout)
- [Install](#install)
- [Daily use](#daily-use)
- [Task reference](#task-reference)
- [Workflow: build infrastructure](#workflow-build-infrastructure)
- [Workflow: manual CLI](#workflow-manual-cli)
- [Web console](#web-console)
- [Configuration](#configuration)
- [Isolation from real AWS](#isolation-from-real-aws)
- [Uninstall](#uninstall)
- [Troubleshooting](#troubleshooting)
- [Limits](#limits)
- [Reference](#reference)

---

## What this is

Floci is a local AWS emulator. It speaks the real AWS wire protocol on port
4566, so the AWS CLI, the AWS SDKs, OpenTofu, and Terraform work against it with
no code changes — only an endpoint override.

Two tiers run side by side:

| Component | Role | Repository |
| --- | --- | --- |
| `floci-lab/` | Your emulator config and your OpenTofu code | This lab (yours) |
| `floci-ui/` | AWS-Console-style web UI, an upstream clone | `floci-io/floci-ui` |

The UI is a **companion, not part of the emulator**. It is a separate process
that calls the same HTTP API your CLI calls. Delete it and the emulator is
unaffected.

```
Browser :4500 ──► floci-ui ──► floci-api :4501 ──► floci :4566
                                                     ▲
AWS CLI / OpenTofu ──────────────────────────────────┘
```

Both stacks join one shared Docker network, `floci-net`. This is what lets the
console reach the emulator by name.

---

## Requirements

- Docker 20.10 or later, with `docker compose` v2 (the plugin, not the
  standalone `docker-compose` binary)
- [mise](https://mise.jdx.dev/) for task running and environment loading
- macOS or Linux

The lab is developed on **Colima**. Docker Desktop, OrbStack, and Rancher
Desktop also work. Check your active runtime with `docker context ls`.

`tofu` and `aws` are installed by mise — see [`[tools]`](#configuration).

---

## Layout

```
floci/
├── mise.toml                     # All tasks and lab environment variables
├── floci-lab/                    # Yours — version-control this
│   ├── docker-compose.yml        # The emulator
│   ├── aws/
│   │   ├── config                # Lab-only AWS CLI config
│   │   └── credentials           # Lab-only dummy credentials
│   ├── provider.tf               # OpenTofu provider, pointed at localhost:4566
│   ├── main.tf                   # Your infrastructure
│   └── data/                     # Emulator state (gitignored)
└── floci-ui/                     # Upstream clone — do not edit
    └── docker-compose.override.yml   # Attaches the UI to floci-net
```

---

## Install

Do this once, or after `mise run uninstall`.

1. Change to the lab root:

   ```bash
   cd ~/floci
   ```

2. Trust the mise config. This lets mise load the lab environment variables.

   ```bash
   mise trust
   ```

3. Run the install task. It creates the network, makes the directories, pulls
   the images, and initializes OpenTofu.

   ```bash
   mise run install
   ```

4. Start the stack:

   ```bash
   mise run up
   ```

5. Make sure both tiers answer:

   ```bash
   mise run health
   ```

Open `http://localhost:4500`. The runtime must show as connected.

---

## Daily use

```bash
mise run up        # Start the emulator and the console
mise run status    # Show what is running
mise run down      # Stop everything
```

The lab environment variables load automatically when you enter the folder. You
do not need to source anything.

Make sure the AWS CLI points at the lab, not at real AWS:

```bash
aws configure list
```

The `config-file` row must show a path inside `floci-lab/`.

---

## Task reference

| Task | What it does |
| --- | --- |
| `mise run install` | Creates the network, pulls images, runs `tofu init`. Run once. |
| `mise run up` | Starts the emulator and the console. Creates the network if it is missing. |
| `mise run down` | Stops both stacks. Keeps data and images. |
| `mise run status` | Lists containers on `floci-net` with their ports. |
| `mise run health` | Checks that the emulator and the console API answer. |
| `mise run logs` | Follows the emulator logs. Press `Ctrl+C` to stop. |
| `mise run reset` | Stops everything and deletes emulator data. Keeps images. |
| `mise run uninstall` | Removes containers, images, the network, and data. Asks for confirmation. |
| `mise tasks` | Lists all tasks. |

`up` depends on the network task, so the shared network is always created before
the containers start. This is the failure that otherwise recurs after a
`docker system prune`.

---

## Workflow: build infrastructure

This is the loop the lab exists for. Write declarative infrastructure, apply it,
check it, destroy it, repeat. Each cycle takes seconds and costs nothing.

### 1. Write the resources

`floci-lab/main.tf`:

```hcl
resource "aws_s3_bucket" "assets" {
  bucket = "lab-assets"
}

resource "aws_sqs_queue" "orders" {
  name = "lab-orders"
}

resource "aws_sns_topic" "events" {
  name = "lab-events"
}

resource "aws_sns_topic_subscription" "orders_sub" {
  topic_arn = aws_sns_topic.events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.orders.arn
}

resource "aws_dynamodb_table" "items" {
  name         = "lab-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

output "queue_url" {
  value = aws_sqs_queue.orders.url
}
```

### 2. Plan and apply

```bash
cd floci-lab
tofu plan
tofu apply
```

### 3. Verify the resources exist

```bash
aws s3 ls
aws sqs list-queues
aws sns list-topics
aws dynamodb list-tables
```

### 4. Verify the resources are connected

This is the test that matters. Step 3 shows that things exist. This step shows
that they are wired together.

Publish a message to the topic:

```bash
aws sns publish \
  --topic-arn "$(aws sns list-topics --query 'Topics[0].TopicArn' --output text)" \
  --message "test event"
```

Read it from the queue:

```bash
aws sqs receive-message --queue-url "$(tofu output -raw queue_url)"
```

A message body must appear. An empty result means the subscription did not
deliver.

### 5. Destroy and rebuild

```bash
tofu destroy
tofu apply
```

Run this loop often. A stack that applies once but fails on the second apply has
a real defect — usually a hardcoded name or a missing dependency. Finding it
here costs nothing.

---

## Workflow: manual CLI

Use raw CLI calls to check the emulator before you blame your HCL. If a CLI call
fails, the problem is Floci or your endpoint.

```bash
# Identity
aws sts get-caller-identity

# S3 round trip
aws s3 mb s3://manual-test
echo "hello" > /tmp/hello.txt
aws s3 cp /tmp/hello.txt s3://manual-test/hello.txt
aws s3 cp s3://manual-test/hello.txt /tmp/back.txt && cat /tmp/back.txt
aws s3 rb s3://manual-test --force

# DynamoDB
aws dynamodb put-item --table-name lab-items \
  --item '{"id":{"S":"1"},"name":{"S":"first"}}'
aws dynamodb scan --table-name lab-items
```

### Multi-account isolation

Floci reads a 12-digit access key as the account ID. Resources in one account
are invisible to another.

```bash
AWS_ACCESS_KEY_ID=111111111111 aws sqs create-queue --queue-name orders
AWS_ACCESS_KEY_ID=222222222222 aws sqs list-queues   # empty
```

Any other key format falls back to `FLOCI_DEFAULT_ACCOUNT_ID`, which defaults to
`000000000000`.

---

## Web console

Open `http://localhost:4500` after `mise run up`.

The console shows only real data returned by the emulator. There are no demo
rows. A service marked unavailable means something real.

**Good coverage today:** S3 (object browser, upload, download, delete), EC2
(launch, start, stop, terminate, AMIs, console output), VPC and subnets, Lambda
(create, invoke, tailed logs), Secrets Manager.

**Thin or missing:** DynamoDB is not rebuilt into the current explorer model.
RDS is list-and-inspect only. There is no SQS or SNS page.

Use the console as an **inspector, not a control panel**. Clicking "create
bucket" builds the habit this lab exists to replace. Opening the console after
`tofu apply` to see what your HCL produced is the useful part.

To update the console:

```bash
cd floci-ui && git pull
mise run down && mise run up
```

---

## Configuration

### Emulator — `floci-lab/docker-compose.yml`

| Variable | Value here | Why |
| --- | --- | --- |
| `FLOCI_DEFAULT_REGION` | `us-east-1` | Matches the OpenTofu provider. |
| `FLOCI_STORAGE_MODE` | `wal` | Durable. State survives a hard stop. |

Storage modes, fastest to safest:

- `memory` — all in RAM, lost on stop. Best for CI.
- `hybrid` — in-memory with async disk flush. Default. A hard kill can lose the
  last few writes.
- `wal` — write-ahead log, maximum durability. Used here, because state that
  disagrees with your OpenTofu state file costs an hour of confusion and the
  write speed does not matter at this scale.

The image tag is pinned (`1.5.11`), not `latest`. An image that changed under
you is a bad first thing to debug.

The Docker socket is mounted. Floci needs it to spawn real containers for
Lambda, RDS, ElastiCache, ECS, and EKS.

> **Caution:** The socket mount gives the container control of your Docker
> daemon. Use this on a development machine only.

### Networking

Both compose files attach to an external network named `floci-net`. The lab
service carries the alias `localhost.floci.io`, which the console needs for
virtual-host-style S3 addresses. Without the alias, bucket browsing fails while
everything else looks connected.

The UI override retargets the base file's `floci_default` network key at
`floci-net`:

```yaml
networks:
  floci_default:
    name: floci-net
    external: true
```

The UI stack is started with `--no-deps floci-api floci-ui` so its own bundled
emulator never starts and never collides on port 4566.

### mise `[tools]`

`opentofu` and `awscli` are pinned in `mise.toml`. Remove the block if you
manage those elsewhere, to avoid a second conflicting install. Pin exact
versions rather than `latest` if you want the lab reproducible next year.

---

## Isolation from real AWS

The lab never reads or writes `~/.aws`. `mise.toml` sets:

```
AWS_CONFIG_FILE            = floci-lab/aws/config
AWS_SHARED_CREDENTIALS_FILE = floci-lab/aws/credentials
AWS_PROFILE                 = default
```

Confirm the isolation:

1. Inside the lab folder, run `aws configure list`. The file paths must point
   into `floci-lab/`.
2. Open a shell outside the lab folder. Run `aws sts get-caller-identity`. Your
   real identity must come back.

This is stronger than a named profile. A profile fails open — forget to set
`AWS_PROFILE` and commands silently hit real AWS. Here the real credentials file
is not on the search path at all.

The OpenTofu provider hardcodes its endpoints and credentials, so it is isolated
regardless of your shell. Keep it that way. Do not switch it to a named profile.

The backend is local, so no lab state can reach a real S3 backend:

```hcl
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

---

## Uninstall

```bash
mise run uninstall
```

It asks for confirmation, then removes the containers of both stacks, their
images and volumes, any containers Floci spawned on `floci-net`, the network
itself, and `floci-lab/data`.

It **keeps** your `.tf` files, `mise.toml`, the `floci-ui` clone, and
`terraform.tfstate`.

> **Caution:** After uninstall, the state file describes resources that no
> longer exist. The next `tofu apply` will fail against a fresh emulator. Delete
> the state first:
>
> ```bash
> rm -f floci-lab/terraform.tfstate*
> ```

For data only, keeping images and the network, use `mise run reset` instead.

The task never runs `docker system prune`. That one-liner is scoped to your
whole machine and would remove unrelated containers, images, and networks.

---

## Troubleshooting

### `docker-credential-desktop: executable file not found`

Docker Desktop was uninstalled but `~/.docker/config.json` still names its
credential helper. Every pull then fails, even for public images.

```bash
cp ~/.docker/config.json ~/.docker/config.json.bak
jq 'del(.credsStore)' ~/.docker/config.json > /tmp/dc.json && mv /tmp/dc.json ~/.docker/config.json
```

Check for `credHelpers` entries pointing at `desktop` and delete those too. A
file containing only `{}` is valid.

> **Caution:** Without a credential store, Docker keeps registry credentials as
> plain base64 in `~/.docker/config.json`. That is acceptable for public images.
> Install a real helper if you push to private registries.

### `Bind for 0.0.0.0:4566 failed: port is already allocated`

Two emulators want the same port. The UI stack ships its own Floci.

Always start the UI with `--no-deps`, which `mise run up` does. If it still
happens, find the holder:

```bash
docker ps --filter publish=4566
lsof -i :4566
docker compose -f floci-ui/docker-compose.yml down --remove-orphans
```

### Console shows `Runtime unavailable`

The console API cannot reach the emulator. Check each hop:

```bash
curl http://localhost:4566/_floci/health
docker compose -f floci-ui/docker-compose.yml exec floci-api curl -s http://floci:4566/_floci/health
curl http://localhost:4501/api/clouds/aws/status
```

If the second command fails, the containers are not on the same network:

```bash
docker network inspect floci-net --format '{{range .Containers}}{{.Name}} {{end}}'
```

Both the emulator and `floci-api` must be listed. If not, confirm the override
merged:

```bash
cd floci-ui && docker compose config | grep -A4 '^networks:'
```

`name: floci-net` and `external: true` must appear.

### A compose override seems ignored

Three usual causes. Check in this order.

1. The file is not next to the base `docker-compose.yml`.
2. The service or network key does not match the base file. Confirm the real
   names with `docker compose config --services` and read the merged output of
   `docker compose config`.
3. The container was restarted, not recreated. Environment changes need
   `--force-recreate`.

### `host.docker.internal` does not resolve

Expected on Colima. Containers run inside a Linux VM and that name may point at
the VM rather than at macOS. The lab does not use it — the shared network makes
it unnecessary. Do not reintroduce it.

### One service is unavailable while the cloud is connected

Each service is probed separately. Ask which one is failing:

```bash
curl 'http://localhost:4501/api/clouds/aws/status?services=all'
```

The `errorCode` distinguishes the cases. `operation_not_implemented` means the
emulator does not implement it. `runtime_unavailable` means it cannot be
reached. `operation_not_supported` means the console has no adapter.

### An AWS call fails with an unimplemented error

Most likely a Floci coverage gap, not your mistake. Check the compatibility test
suite in the Floci repository before rewriting working HCL.

---

## Limits

Be clear about what this lab cannot teach you. It determines when you must leave
the emulator.

**No real authorization.** Floci accepts any credentials and has no auth gate.
IAM resources exist as records, but a policy that is wrong, over-permissive, or
missing will still let your apply succeed. The emulator cannot tell you whether
your least-privilege policy works. Verify anything security-related against a
real account.

**No quotas, latency, or cost.** Service limits, eventual consistency, cold
starts, cross-AZ behaviour, and the bill are all absent. If you are learning
infrastructure partly to reason about failure modes under load or about cost,
the emulator is silent on both.

**Not AWS.** It is an independent reimplementation. Coverage is broad but the
edges of each API differ. When something behaves strangely, the first hypothesis
should be "Floci does not implement this," not "I misunderstand AWS."

The honest framing: use this lab for the 90% of learning that is muscle memory —
writing HCL, reading state, wiring services, breaking and fixing things — and
keep a small real AWS account for the 10% that is security, cost, and production
behaviour.

---

## Reference

- Floci docs — https://floci.io
- Floci emulator — https://github.com/floci-io/floci
- Floci UI — https://github.com/floci-io/floci-ui
- Docker Hub — https://hub.docker.com/r/floci/floci
- mise — https://mise.jdx.dev/

Floci is MIT licensed. Port 4566 is the same port LocalStack used, so migrations
usually need no code changes.
