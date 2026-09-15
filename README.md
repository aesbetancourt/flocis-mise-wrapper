# Floci Lab

A local AWS environment for learning and simulating infrastructure. It runs the
[Floci](https://floci.io) emulator, the Floci UI web console, and OpenTofu — all
on your machine, with no AWS account and no cost.

- **Emulator** — `http://localhost:4566`
- **Web console and its API** — `http://localhost:4500`

This README covers install, configuration, and maintenance. To learn, practice,
and test with the lab, read the [usage manual](USAGE.md). For guided exercises
with checkers and solutions, read the
[exercises guide](floci-lab/exercises/README.md).

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
- [Updates](#updates)
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

Two containers run side by side, from one compose file:

| Service | Role | Image |
| --- | --- | --- |
| `floci` | The AWS emulator | `floci/floci` |
| `floci-ui` | AWS-Console-style web UI and its API | `floci/floci-ui` |

The UI is a **companion, not part of the emulator**. It is a separate process
that calls the same HTTP API your CLI calls. Delete it and the emulator is
unaffected.

```
Browser :4500 ──► floci-ui ──► floci :4566
                                  ▲
AWS CLI / OpenTofu ───────────────┘
```

Both containers join one shared Docker network, `floci-net`. This is what lets
the console reach the emulator by name.

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
├── versions.env                  # Pinned Floci image tags
├── USAGE.md                      # Usage manual: learn, practice, test
├── scripts/
│   └── versions.sh               # Logic for outdated, upgrade, backup, rollback
└── floci-lab/                    # Yours — version-control this
    ├── docker-compose.yml        # The emulator and the console
    ├── aws/
    │   ├── config                # Lab-only AWS CLI config
    │   └── credentials           # Lab-only dummy credentials
    ├── provider.tf               # OpenTofu providers, pointed at localhost:4566
    ├── main.tf                   # Your infrastructure
    ├── exercises/                # Six exercises and drills, with checkers and solutions
    ├── scratch/                  # Throwaway files (gitignored)
    ├── data/                     # Emulator state (gitignored)
    └── backups/                  # Upgrade backups (gitignored)
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

5. Make sure both containers answer:

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
aws sts get-caller-identity --query Account --output text
```

The `region` row must show a path inside `floci-lab/`. The account must be
`000000000000`.

---

## Task reference

| Task | What it does |
| --- | --- |
| `mise run install` | Creates the network, pulls images, runs `tofu init`. Run once. |
| `mise run up` | Starts the emulator and the console. Creates the network if it is missing. |
| `mise run down` | Stops the emulator and the console. Keeps data and images. |
| `mise run restart` | Runs `down`, then `up`. |
| `mise run status` | Lists containers on `floci-net` with their images and ports. |
| `mise run health` | Checks the emulator, the console, and the link between them. |
| `mise run logs` | Follows the emulator logs. Press `Ctrl+C` to stop. |
| `mise run logs-ui` | Follows the console logs. |
| `mise run outdated` | Compares pinned versions with the latest releases. Changes nothing. |
| `mise run upgrade` | Upgrades the Floci pins. See [Updates](#updates). |
| `mise run backup` | Saves emulator data and pins to `floci-lab/backups`. |
| `mise run rollback` | Restores data and pins from the newest backup. |
| `mise run reset` | Stops everything and deletes emulator data. Keeps images. |
| `mise run flush` | Stops the lab. Deletes emulator data, backups, and the containers and volumes Floci made. Asks for confirmation. |
| `mise run uninstall` | Removes containers, images, the network, and data. Asks for confirmation. |
| `mise tasks` | Lists all tasks. |

`up` depends on the network task, so the shared network is always created before
the containers start. This is the failure that otherwise recurs after a
`docker system prune`.

---

## Workflow: build infrastructure

This is the loop the lab exists for. Write declarative infrastructure, apply it,
check it, destroy it, repeat. Each cycle takes seconds and costs nothing.

`floci-lab/provider.tf` is ready. It points the AWS provider at the emulator and
keeps state in a local file. `mise run install` runs `tofu init` for it.

> **Note:** The provider lists an endpoint for each service it can use. Before
> you use a service that is not in the `endpoints` block, add a line for it.
> Without the line, the provider calls real AWS and fails.

Commit `floci-lab/.terraform.lock.hcl`. It pins the provider version. To update
the provider, run `tofu init -upgrade` in `floci-lab/`.

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

Set the secret key too. Inside the lab, mise sets it to an empty value, and the
CLI rejects a key without a secret.

```bash
AWS_ACCESS_KEY_ID=111111111111 AWS_SECRET_ACCESS_KEY=test aws sqs create-queue --queue-name orders
AWS_ACCESS_KEY_ID=222222222222 AWS_SECRET_ACCESS_KEY=test aws sqs list-queues   # empty
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

To update the console, see [Updates](#updates).

---

## Configuration

### Emulator — `floci-lab/docker-compose.yml`

| Variable | Value here | Why |
| --- | --- | --- |
| `FLOCI_DEFAULT_REGION` | `us-east-1` | Matches the OpenTofu provider. |
| `FLOCI_STORAGE_MODE` | `wal` | Durable. State survives a hard stop. |
| `FLOCI_SERVICES_UI_ENABLED` | `false` | Emulator 1.5.26 and later start their own console on port 4500. The lab runs its own `floci-ui` service instead. |

Storage modes, fastest to safest:

- `memory` — all in RAM, lost on stop. Best for CI.
- `hybrid` — in-memory with async disk flush. Default. A hard kill can lose the
  last few writes.
- `wal` — write-ahead log, maximum durability. Used here, because state that
  disagrees with your OpenTofu state file costs an hour of confusion and the
  write speed does not matter at this scale.

Both image tags are pinned in `versions.env`, not `latest`. An image that
changed under you is a bad first thing to debug. Compose stops with an error if
a pin is missing, so run compose through mise.

The Docker socket is mounted. Floci needs it to spawn real containers for
Lambda, RDS, ElastiCache, ECS, and EKS.

> **Caution:** The socket mount gives the container control of your Docker
> daemon. Use this on a development machine only.

### Console — `floci-lab/docker-compose.yml`

| Variable | Value here | Why |
| --- | --- | --- |
| `FLOCI_ENDPOINT` | `http://floci:4566` | The emulator, by its service name on `floci-net`. |
| `AWS_REGION` | `us-east-1` | Matches the emulator. |

The image serves the web page and the API from one process on port 4500.

### Networking

Both services attach to an external network named `floci-net`. Floci also puts
the containers it spawns for Lambda, RDS, and ECS on that network.

The emulator carries the alias `localhost.floci.io`, which the console needs for
virtual-host-style S3 addresses. Without the alias, bucket browsing fails while
everything else looks connected.

### mise `[tools]`

`opentofu` and `awscli` are pinned in `mise.toml`. Remove the block if you
manage those elsewhere, to avoid a second conflicting install. Pin exact
versions rather than `latest` if you want the lab reproducible next year.

---

## Updates

| Pin | File | Update with |
| --- | --- | --- |
| Emulator image (`FLOCI_IMAGE_TAG`) | `versions.env` | `mise run upgrade` |
| Console image (`FLOCI_UI_TAG`) | `versions.env` | `mise run upgrade` |
| `opentofu`, `awscli` | `mise.toml` | `mise upgrade --bump` |

Floci ships a release on the first and third Tuesday of each month. Minor
releases can change emulator behavior, so read the changelog for every upgrade.

### Check for new versions

```bash
mise run outdated
```

The task lists each pin, the latest release, and a changelog link. `MAJOR`
marks a new major version. The task changes nothing.

### Upgrade Floci

> **Warning:** An emulator upgrade can convert the data in `floci-lab/data`.
> There is no way to go back to the old format except the backup that the task
> makes.

1. Run the upgrade:

   ```bash
   mise run upgrade                    # Both images to the latest release
   mise run upgrade --floci 2.0.1      # Only the emulator, to this version
   mise run upgrade --ui 0.5.0         # Only the console, to this version
   ```

2. Read the changelog links in the plan.
3. Type `yes` to continue.
4. Commit `versions.env` when the task reports `Upgrade complete`.

The task does these steps in order:

1. Pulls the new images. The lab keeps running, so a failed pull changes
   nothing.
2. Stops the lab and saves `floci-lab/data` and `versions.env` to
   `floci-lab/backups/`.
3. Writes the new pins and starts the lab.
4. Runs `health` for up to 90 seconds and checks the emulator version.
5. If the check fails, prints the emulator logs, restores the backup, and starts
   the old versions again.

### Roll back

Use this when an upgrade passed the health check but breaks your work, for
example a stricter IAM or API Gateway behavior.

> **Caution:** A rollback deletes all emulator data written after the backup.

```bash
mise run rollback
```

The task restores the newest backup: data and pins. Commit `versions.env` after
the rollback.

### Backups

- `mise run upgrade` makes a backup automatically.
- `mise run backup` makes one on demand. It stops the lab, saves, and starts
  the lab again.
- The lab keeps the five newest backups. It deletes older ones.
- `mise run uninstall` and `mise run reset` do not delete backups.
  `mise run flush` deletes them.
- A backup contains `floci-lab/data` only. Container services such as RDS keep
  their data in Docker volumes that Floci makes. Backups do not include those
  volumes.

### Update the tools

```bash
mise upgrade --bump opentofu
cd floci-lab && tofu init -upgrade
```

`--bump` writes the new version into `mise.toml`. Commit it.

---

## Isolation from real AWS

Inside the lab folder, the AWS CLI does not read `~/.aws`. `mise.toml` sets:

```
AWS_CONFIG_FILE             = floci-lab/aws/config
AWS_SHARED_CREDENTIALS_FILE = floci-lab/aws/credentials
AWS_PROFILE                 = floci
```

The `floci` profile sets `endpoint_url = http://localhost:4566`, so every CLI
call goes to the emulator.

The AWS CLI reads some environment variables before these files. Examples are
exported access keys, session tokens, web identity roles, and endpoint
overrides. `mise.toml` sets each of them to an empty value inside the lab. The
CLI treats an empty value as not set. A real-account session in your shell
cannot reach into the lab, and mise restores it when you leave the folder.

> **Note:** Do not replace the empty values with `false`. In mise, `false` does
> not remove a variable that the shell already exported.

Confirm the isolation:

1. Inside the lab folder, run `aws sts get-caller-identity`. The account must be
   `000000000000`.
2. Open a shell outside the lab folder. Run `aws sts get-caller-identity`. Your
   real identity must come back.

> **Warning:** The isolation works only when mise loads the lab environment. A
> script, IDE task, or cron job that runs without mise reads `~/.aws` and uses
> your real account.

Run lab commands through `mise run` or `mise exec`. In scripts, also pass
`--profile floci`. Without mise, that profile does not exist, so the command
fails instead of reaching real AWS.

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

It asks for confirmation, then removes the emulator and console containers,
their images and volumes, the containers and volumes Floci made, the
`floci-net` network, and `floci-lab/data`.

Floci labels each container and volume it makes with
`floci_emulator=floci-aws`. The task removes only those. Your own containers on
`floci-net` stay.

It **keeps** your `.tf` files, `mise.toml`, `versions.env`, the backups in
`floci-lab/backups`, and `terraform.tfstate`.

> **Caution:** After uninstall, the state file describes resources that no
> longer exist. The next `tofu apply` will fail against a fresh emulator. Delete
> the state first:
>
> ```bash
> rm -f floci-lab/terraform.tfstate*
> ```

For data only, keeping images and the network, use `mise run reset` instead.
To also delete the backups and the containers and volumes Floci made, use
`mise run flush`.

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

### `Bind for 0.0.0.0:4566 failed` or `0.0.0.0:4500 failed: port is already allocated`

Another container holds the port. Usual holders:

- A second emulator, for example LocalStack.
- The console that emulator 1.5.26 and later start by themselves, named
  `floci-ui`. It appears if `FLOCI_SERVICES_UI_ENABLED: "false"` is missing from
  the compose file.

Find the holder:

```bash
docker ps --filter publish=4566 --filter publish=4500
lsof -i :4566 -i :4500
```

### Console shows `Runtime unavailable`

The console cannot reach the emulator. Check each hop:

```bash
curl http://localhost:4566/_floci/health
curl http://localhost:4500/api/clouds/aws/status
mise run health
```

The status response must contain `"runtime":"reachable"`. If it does not, make
sure both containers are on the same network:

```bash
docker network inspect floci-net --format '{{range .Containers}}{{.Name}} {{end}}'
```

Both `floci-lab-floci-1` and `floci-lab-floci-ui-1` must be listed.

### `required variable FLOCI_IMAGE_TAG is missing a value`

Compose ran without the lab environment. Run it through mise:

```bash
mise exec -- docker compose -f floci-lab/docker-compose.yml ps
```

### An upgrade rolled back

The task printed the last emulator log lines before it restored the backup. To
try again with an older release, name the version:

```bash
mise run outdated
mise run upgrade --floci <version>
```

### `host.docker.internal` does not resolve

Expected on Colima. Containers run inside a Linux VM and that name may point at
the VM rather than at macOS. The lab does not use it — the shared network makes
it unnecessary. Do not reintroduce it.

### One service is unavailable while the cloud is connected

Each service is probed separately. Ask which one is failing:

```bash
curl 'http://localhost:4500/api/clouds/aws/status?services=all'
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
