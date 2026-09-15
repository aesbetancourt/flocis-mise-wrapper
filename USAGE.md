# Floci Test Bench — Usage Manual

This lab is a personal AWS test bench. Use it to learn AWS services, practice
infrastructure as code, and test application code with the AWS CLI or an AWS
SDK. Everything runs on your machine. No call reaches a real AWS account, and
nothing costs money.

For install, configuration, updates, and troubleshooting, read the
[README](README.md).

All recipes in this manual were tested on Floci emulator 2.1.0 and console
0.5.0.

## Contents

1. [How the bench works](#1-how-the-bench-works)
2. [Start and end a session](#2-start-and-end-a-session)
3. [Choose a way to work](#3-choose-a-way-to-work)
4. [Work with the AWS CLI](#4-work-with-the-aws-cli)
5. [Work with OpenTofu](#5-work-with-opentofu)
6. [Connect your own apps with an AWS SDK](#6-connect-your-own-apps-with-an-aws-sdk)
7. [Know what is real and what is a stub](#7-know-what-is-real-and-what-is-a-stub)
8. [Learning path](#8-learning-path)
9. [Keep the bench healthy](#9-keep-the-bench-healthy)
10. [Quick reference](#10-quick-reference)

---

## 1. How the bench works

```mermaid
flowchart LR
  CLI[AWS CLI] --> E
  TF[OpenTofu] --> E
  APP[Your app + AWS SDK] --> E
  B[Browser] --> UI[Console :4500] --> E[Floci emulator :4566]
  E --> D[(floci-lab/data)]
  E --> C[Containers for Lambda, RDS, ...]
```

| Part | Role |
| --- | --- |
| Floci emulator, `localhost:4566` | Answers AWS API calls. Uses the fake account `000000000000`. |
| Floci console, `localhost:4500` | Shows what exists in the emulator. |
| mise | Loads the lab environment when you enter the lab folder. Runs the lab tasks. |
| AWS CLI and OpenTofu | Installed and pinned by mise. Inside the lab folder, they use the emulator. |

### What "create" means in Floci

Floci does not create anything in AWS. It makes one of three things:

| Floci makes | For | Where it lives |
| --- | --- | --- |
| A record | Most resources: queues, messages, topics, tables, roles, parameters, VPCs | `floci-lab/data/<service>-<type>.wal` |
| A file | S3 object contents | `floci-lab/data/s3/.accounts/<account>/<bucket>/<key>.s3data` |
| A real container | Lambda, RDS, ElastiCache, MSK, MWAA, ECS, EKS, OpenSearch, DocumentDB, Redshift, ECR | Docker, on the `floci-net` network |

Records and files are fast and use almost no resources. Containers run the real
software, use memory in the Docker VM, and take seconds to start.

---

## 2. Start and end a session

1. Go to the lab folder:

   ```bash
   cd ~/Dev/personal/floci
   ```

2. Start the lab:

   ```bash
   mise run up
   ```

3. Make sure the lab is healthy:

   ```bash
   mise run health
   ```

   All three lines must show `OK`.

4. Make sure the lab environment is loaded:

   ```bash
   echo $AWS_PROFILE    # must show: floci
   ```

5. Open the console at `http://localhost:4500`.

To end the session, stop the lab:

```bash
mise run down
```

The data stays in `floci-lab/data`. The next `mise run up` starts with the same
resources.

---

## 3. Choose a way to work

| Goal | Use | Section |
| --- | --- | --- |
| Learn what a service does | AWS CLI | [4](#4-work-with-the-aws-cli) |
| Practice infrastructure as code | OpenTofu | [5](#5-work-with-opentofu) |
| Test application code | An AWS SDK in your app | [6](#6-connect-your-own-apps-with-an-aws-sdk) |
| See the result | Console, `localhost:4500` | — |

Use the console to inspect, not to create. Create resources with the CLI,
OpenTofu, or code, the same way you work on real AWS.

A good order for each new service: learn it with the CLI, then describe it in
OpenTofu, then call it from an app.

---

## 4. Work with the AWS CLI

### Rules

- Run `aws` inside the lab folder or a subfolder. There, the CLI uses the
  `floci` profile and sends each call to the emulator.
- Outside the lab folder, the same command uses your real AWS account.
- Keep throwaway files in `floci-lab/scratch/`. Git ignores that folder, and the
  lab environment applies there.

> **Warning:** A script that runs from an IDE, cron, or a Git hook can run
> without mise. Then it uses your real AWS account. Pass `--profile floci` in
> every lab script. Without mise, that profile does not exist, so the command
> fails.

Before the recipes, go to the scratch folder:

```bash
mkdir -p floci-lab/scratch && cd floci-lab/scratch
```

### S3: upload and download

```bash
aws s3 mb s3://practice
echo "hello" | aws s3 cp - s3://practice/hello.txt
aws s3 cp s3://practice/hello.txt -
aws s3 rb s3://practice --force
```

### SQS: send and receive a message

```bash
Q=$(aws sqs create-queue --queue-name jobs --query QueueUrl --output text)
aws sqs send-message --queue-url "$Q" --message-body "job 1"
aws sqs receive-message --queue-url "$Q" --wait-time-seconds 5
aws sqs delete-queue --queue-url "$Q"
```

### SNS to SQS: fan-out

```bash
Q=$(aws sqs create-queue --queue-name orders --query QueueUrl --output text)
QARN=$(aws sqs get-queue-attributes --queue-url "$Q" \
  --attribute-names QueueArn --query Attributes.QueueArn --output text)
T=$(aws sns create-topic --name events --query TopicArn --output text)

aws sns subscribe --topic-arn "$T" --protocol sqs --notification-endpoint "$QARN"
aws sns publish --topic-arn "$T" --message "order created"
aws sqs receive-message --queue-url "$Q" --wait-time-seconds 5 \
  --query 'Messages[0].Body' --output text

aws sns delete-topic --topic-arn "$T"
aws sqs delete-queue --queue-url "$Q"
```

The message body is an SNS `Notification` JSON envelope, as on real AWS. To get
the plain message, add `--attributes RawMessageDelivery=true` to `subscribe`.

### DynamoDB: write and read an item

```bash
aws dynamodb create-table --table-name items \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

aws dynamodb put-item --table-name items \
  --item '{"id":{"S":"1"},"name":{"S":"first"}}'
aws dynamodb get-item --table-name items --key '{"id":{"S":"1"}}'

aws dynamodb delete-table --table-name items
```

### Lambda: deploy and invoke a Python function

```bash
cat > handler.py <<'EOF'
def handler(event, context):
    return {"greeting": f"hello {event.get('name', 'world')}"}
EOF
zip function.zip handler.py

aws lambda create-function --function-name hello \
  --runtime python3.12 --handler handler.handler \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --zip-file fileb://function.zip
aws lambda wait function-active-v2 --function-name hello

aws lambda invoke --function-name hello \
  --cli-binary-format raw-in-base64-out \
  --payload '{"name":"floci"}' out.json
cat out.json    # {"greeting": "hello floci"}

aws lambda delete-function --function-name hello
```

- The first invoke takes about 15 seconds, because Floci starts a container for
  the function. The next invokes are fast.
- The role in `--role` does not need to exist.
- Deleting the function also removes its container.

### Separate accounts

Floci reads a 12-digit access key as the account ID. Resources in one account
are invisible to another.

```bash
AWS_ACCESS_KEY_ID=111111111111 AWS_SECRET_ACCESS_KEY=test aws sqs create-queue --queue-name orders
AWS_ACCESS_KEY_ID=222222222222 AWS_SECRET_ACCESS_KEY=test aws sqs list-queues   # empty
```

Set both variables. Inside the lab, mise sets the secret key to an empty value,
and the CLI rejects an access key without a secret key.

---

## 5. Work with OpenTofu

`floci-lab/provider.tf` is ready. It sends each AWS service to the emulator,
uses dummy credentials, and keeps state in a local file.

> **Warning:** The provider has one endpoint line for each service it can use.
> A service without a line sends its calls to real AWS, and they fail. Add a
> line to the `endpoints` block before you use a new service.

### The practice loop

Run these commands in `floci-lab/`:

1. Write the resources in `main.tf`.
2. Preview the changes:

   ```bash
   tofu plan
   ```

3. Apply the changes:

   ```bash
   tofu apply
   ```

4. Prove that the system works with real traffic. For example, publish a
   message, upload a file, or invoke a function with the CLI.
5. Look at the result in the console.
6. Destroy the resources:

   ```bash
   tofu destroy
   ```

7. Apply again. If the second apply fails, the code has a real defect, often a
   hard-coded name or a missing dependency.

For a full example with S3, SQS, SNS, and DynamoDB, read
[Workflow: build infrastructure](README.md#workflow-build-infrastructure).

### Separate exercise folders

Give each exercise its own folder and its own state. Then a broken exercise
does not block the others.

`floci-lab/.terraform` must exist first. `mise run install` or `tofu init` in
`floci-lab/` makes it.

1. Make the folder and copy the provider files:

   ```bash
   mkdir -p floci-lab/exercises/01-s3 && cd floci-lab/exercises/01-s3
   cp ../../provider.tf ../../.terraform.lock.hcl .
   ```

2. Initialize with the provider that is already downloaded (about 770 MB):

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   ```

Git ignores `.terraform/` and state files in every folder.

### Drills

| Drill | Do this | Learn |
| --- | --- | --- |
| Drift | Change a resource with the CLI. Run `tofu plan`. | How tofu detects changes made outside the code. |
| Lost state | Delete `terraform.tfstate`. Rebuild it with `tofu import`. | What state is and how to recover it. |
| Broken wiring | Give a subscription a wrong queue ARN. Predict the plan, then run it. | How references connect resources. |
| Rename | Rename a resource block. Read the plan. | Why a rename destroys and creates, and how `moved` blocks stop it. |

---

## 6. Connect your own apps with an AWS SDK

Any AWS SDK works with the emulator. Configure the app with environment
variables. Then the app code stays the same as for real AWS.

### App on your Mac

Give the app its own environment in its own folder. Example for the app's
`mise.toml`:

```toml
[env]
AWS_ENDPOINT_URL      = "http://localhost:4566"
AWS_REGION            = "us-east-1"
AWS_DEFAULT_REGION    = "us-east-1"   # boto3 reads only this one
AWS_ACCESS_KEY_ID     = "test"
AWS_SECRET_ACCESS_KEY = "test"
```

> **Warning:** Set all five variables together. With only the endpoint, the SDK
> takes your real keys from `~/.aws`. With only the keys, the calls go to real
> AWS and fail.

The app code has no Floci settings. This Python app was tested from a folder
outside the lab:

```python
import boto3

sqs = boto3.client("sqs")
url = sqs.create_queue(QueueName="orders")["QueueUrl"]
sqs.send_message(QueueUrl=url, MessageBody="hello")
print(sqs.receive_message(QueueUrl=url, WaitTimeSeconds=2)["Messages"][0]["Body"])
```

Older SDK versions can ignore `AWS_ENDPOINT_URL`. Then set the endpoint in the
client code, as the
[Floci SDK setup page](https://github.com/floci-io/floci/blob/main/docs/getting-started/aws-setup.md)
shows.

### App in a Docker container

Inside a container, `localhost` is the container itself. Connect the container
to the lab network, and use the emulator service name:

```yaml
services:
  my-app:
    environment:
      AWS_ENDPOINT_URL: http://floci:4566
      AWS_REGION: us-east-1
      AWS_DEFAULT_REGION: us-east-1
      AWS_ACCESS_KEY_ID: test
      AWS_SECRET_ACCESS_KEY: test
    networks: [floci-net]

networks:
  floci-net:
    external: true
```

The lab console uses this method to reach the emulator.

For S3 in a container, turn on path-style addresses in the SDK:

| SDK | Setting |
| --- | --- |
| JavaScript v3 | `forcePathStyle: true` |
| Go v2 | `o.UsePathStyle = true` |
| Java v2 | `.forcePathStyle(true)` |
| Python boto3 | `Config(s3={"addressing_style": "path"})` |

On your Mac, S3 works without this setting.

### Automated tests

Do not point automated tests at the lab. Test data then mixes with your practice
data. Use a Testcontainers module instead. It starts a new emulator for each
test run:

- [Java](https://github.com/floci-io/testcontainers-floci)
- [Go](https://github.com/floci-io/testcontainers-floci-go)
- [.NET](https://github.com/floci-io/testcontainers-floci-dotnet)
- [Python](https://github.com/floci-io/testcontainers-floci-python)
- [Node](https://github.com/floci-io/testcontainers-floci-node)

### Keep apps apart

Give each app its own 12-digit access key, for example `111111111111` and
`222222222222`. Each app then sees only its own resources in the shared
emulator.

---

## 7. Know what is real and what is a stub

Floci imitates AWS. The depth of the imitation changes from service to service.

| Level | What you get | Examples |
| --- | --- | --- |
| Emulated behavior | Resources act like AWS: messages move, items persist, objects store bytes. | S3, SQS, SNS, DynamoDB |
| Real engine | Floci starts the real software in a container. | Lambda, RDS, ElastiCache, ECS, EKS, OpenSearch |
| Stub | Responses have the correct shape, but no real work happens. | Transcribe, Bedrock Runtime |
| Not implemented | The call fails with `UnknownOperationException`. | `aws bedrock list-foundation-models` |

Before you depend on a service, read its page in the
[Floci service docs](https://github.com/floci-io/floci/tree/main/docs/services).

### Stub examples

| Call | Result |
| --- | --- |
| `aws transcribe start-transcription-job` | `COMPLETED` at once, even when the audio file does not exist. The transcript file is never created. |
| `aws bedrock-runtime converse` | Always `"Floci stub response for model=<model>"`, with the same token counts. |

Stubs are good for testing the flow of your code: request shapes, job status,
error handling, and IAM wiring. They cannot give real transcripts or real model
answers.

### Real text from Bedrock

The emulator can forward `converse` and `converse-stream` calls to an
OpenAI-compatible server, for example Ollama. Add these variables to the `floci`
service in `floci-lab/docker-compose.yml`, then run `mise run restart`:

```yaml
FLOCI_SERVICES_BEDROCK_RUNTIME_BACKEND: proxy
FLOCI_SERVICES_BEDROCK_RUNTIME_PROXY_URL: http://<ollama-host>:11434/v1
FLOCI_SERVICES_BEDROCK_RUNTIME_PROXY_DEFAULT_MODEL: llama3.2
```

The answers then come from that model, not from Claude. `invoke-model` still
returns the stub response.

### What the bench cannot teach

- **IAM least privilege.** Floci does not fully enforce IAM policies. A wrong
  policy can still work here. Test security on a real account.
- **Cost, quotas, latency, and failure under load.** These do not exist in the
  emulator.

Keep a small real AWS account for these topics.

---

## 8. Learning path

Do the levels in order. For each level, use the CLI first, then OpenTofu, then
an app with an SDK.

| Level | Build | Learn |
| --- | --- | --- |
| 1. Basics | S3 bucket with versioning and a lifecycle rule | `plan`, `apply`, `destroy`, state, outputs |
| 2. Messaging | SNS topic to two SQS queues, with a dead-letter queue | Resource wiring, queue policies, retries |
| 3. Serverless API | API Gateway to Lambda to DynamoDB | Lambda packaging, IAM roles, CloudWatch Logs |
| 4. Event-driven | S3 upload to EventBridge to Lambda to Step Functions | Event patterns, orchestration, end-to-end tests |
| 5. Reusable code | Levels 2 and 3 as modules with `for_each` and variables | Module design, `tofu test` |
| 6. Containers | ECR image to an ECS service | Container workloads. Floci runs real containers here, so it is slower. |

Do the [drills](#drills) at any level.

---

## 9. Keep the bench healthy

| When | Run | Result |
| --- | --- | --- |
| Before a risky experiment | `mise run backup` | Saves data and pins to `floci-lab/backups/`. |
| After a failed experiment | `mise run rollback` | Restores the newest backup. Data written after it is lost. |
| For an empty emulator | `mise run reset` | Deletes all emulator data. Keeps backups. |
| Every few weeks | `mise run outdated` | Shows new Floci releases. Changes nothing. |
| To update Floci | `mise run upgrade` | See [Updates](README.md#updates). |
| The Mac feels slow | `mise run status` | Lists the containers. Delete the resources you do not need. |

`mise run reset` does not delete OpenTofu state. Run `tofu destroy` first, or
delete the state files. Otherwise the state lists resources that no longer
exist.

---

## 10. Quick reference

| I want to | Run |
| --- | --- |
| Start the bench | `mise run up` |
| Check the bench | `mise run health` |
| Stop the bench | `mise run down` |
| Make sure the CLI uses the lab | `echo $AWS_PROFILE` shows `floci` |
| Check the account | `aws sts get-caller-identity` shows `000000000000` |
| Open the console | `http://localhost:4500` |
| Follow emulator logs | `mise run logs` |
| Save a restore point | `mise run backup` |
| Go back to the restore point | `mise run rollback` |
| Delete all emulator data | `mise run reset` |
| Check for updates | `mise run outdated` |
| List all tasks | `mise tasks` |

| Endpoint | Use from |
| --- | --- |
| `http://localhost:4566` | The CLI, OpenTofu, and apps on your Mac |
| `http://floci:4566` | Containers on the `floci-net` network |
| `http://localhost:4500` | Your browser |
