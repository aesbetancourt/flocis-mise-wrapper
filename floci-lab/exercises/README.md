# Exercises

Hands-on exercises for the Floci test bench. Each exercise builds a small, real
system in three ways: with the AWS CLI, with OpenTofu, and from Python code. A
checker script tells you when the result is correct.

All exercises and solutions were tested on Floci emulator 2.1.0 and OpenTofu
1.9.0. Each README marks the places where Floci differs from real AWS with a
**Note**.

For how the bench works, read the [usage manual](../../USAGE.md).

---

## The exercises

Do them in order. Each level uses skills from the level before.

| # | Exercise | Services | Time |
| --- | --- | --- | --- |
| 1 | [S3 basics](01-s3-basics/) | S3 | 30–45 min |
| 2 | [Messaging](02-messaging/) | SNS, SQS | 45–60 min |
| 3 | [Serverless API](03-serverless-api/) | API Gateway, Lambda, DynamoDB, IAM, CloudWatch Logs | 60–90 min |
| 4 | [Event-driven](04-event-driven/) | S3, EventBridge, SQS, EventBridge Pipes, Step Functions, Lambda, DynamoDB | 90–120 min |
| 5 | [Modules and tests](05-modules-and-tests/) | SQS, OpenTofu modules and `tofu test` | 60–90 min |
| 6 | [Containers](06-containers/) | ECR, ECS, IAM, CloudWatch Logs | 60–90 min |
| — | [Drills](drills/) | Drift, lost state, broken wiring, renames | 10–20 min each |

Exercise 06 needs about 300 MB of free Docker memory. It pushes images with a
BuildKit option, because a plain `docker push` to Floci ECR fails on Docker with
the containerd image store. The exercise README explains it.

Do the drills at any time after exercise 2.

---

## Before you start

1. Make sure the lab runs:

   ```bash
   mise run health
   ```

2. Make sure these tools are available:

   | Tool | Used for | Check |
   | --- | --- | --- |
   | `uv` | Part C Python code | `uv --version` |
   | `jq` | The exercise 03 checker | `jq --version` |
   | Docker memory | Lambda in 03 and 04, ECS in 06 | `docker info --format '{{.MemTotal}}'` |

3. Make sure the lab provider is downloaded. `floci-lab/.terraform/providers`
   must exist. If it does not, run `tofu init` in `floci-lab/` one time.

---

## How an exercise works

```
NN-name/
├── README.md        # Goal, steps, questions, hints
├── main.tf          # Starter code with TODOs (Part B)
├── app.py           # Starter code with TODOs (Part C)
├── check.sh         # Checks the result in the emulator
├── provider.tf      # Link to the lab provider. Do not edit.
└── solution/        # A working answer
```

| Part | You do | Tool |
| --- | --- | --- |
| A — Explore | Build a small version by hand and watch how the service acts | AWS CLI |
| B — Build | Complete the TODOs and apply them | OpenTofu |
| C — Use | Complete the TODOs and run the code against your resources | Python and boto3 |
| Check | Run `./check.sh` | Bash and the AWS CLI |

### Steps for each exercise

1. Read the README from the top.
2. Do Part A in the exercise folder.
3. Initialize OpenTofu:

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   ```

4. Do Part B and Part C.
5. Run the checker:

   ```bash
   ./check.sh
   ```

6. Answer the **Question** prompts in the README.
7. Do the Clean up section.

---

## Rules

- **Names.** Each exercise uses its own prefix, for example `ex03-`. Exercises
  do not collide with each other.
- **Your answer or the solution, not both.** Your files and `solution/` use the
  same names. Destroy one before you apply the other.
- **Clean up.** Destroy each exercise when you finish. Lambda and ECS
  containers use memory until you delete them.
- **Look at the solution last.** Use the Hints section first.
- **Restore point.** Run `mise run backup` before an exercise if the emulator
  holds data you want to keep.

---

## The checker

`check.sh` reads the emulator, not your files. It prints `PASS` or `FAIL` for
each check.

| Exit code | Meaning |
| --- | --- |
| `0` | All checks passed. |
| `1` | One or more checks failed. Read the Hints section. |
| `2` | The checker did not run: the lab environment is not loaded, or the emulator does not answer. |

The checker uses `aws --profile floci` for every call. Without the lab
environment, that profile does not exist, so a checker cannot reach a real AWS
account.

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `tofu init` cannot find the provider | Run `tofu init` in `floci-lab/` one time, then run the exercise init again. |
| `check.sh` exits with `2` | Run it from a folder inside the lab, in a shell where mise is active. Run `mise run up` if the emulator is stopped. |
| An apply fails with "already exists" | Your answer and the solution both ran. Destroy one of them. |
| `tofu destroy` does not end on an S3 bucket | Empty the bucket with `aws s3 rm s3://<bucket> --recursive`, then destroy again. See exercise 04. |
| The Mac is slow | Run `mise run status`. Destroy the exercises that you do not use. |
| The emulator holds too much old data | Run `mise run reset`, or `mise run flush` to also delete backups. Delete old `terraform.tfstate` files after that. |
