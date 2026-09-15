# Exercises

Hands-on exercises for the Floci test bench. Each exercise builds a small, real
system in three ways: with the AWS CLI, with OpenTofu, and from Python code. A
checker script tells you when the result is correct.

All exercises and solutions were tested on Floci emulator 2.1.0 and OpenTofu
1.9.0. Each exercise README marks the places where Floci differs from real AWS
with a **Note**.

For how the bench works, read the [usage manual](../../USAGE.md).

## Contents

1. [The exercises](#1-the-exercises)
2. [Before you start](#2-before-you-start)
3. [How the folder is organized](#3-how-the-folder-is-organized)
4. [How an exercise README is organized](#4-how-an-exercise-readme-is-organized)
5. [Work through an exercise](#5-work-through-an-exercise)
6. [Use the checker](#6-use-the-checker)
7. [Use the solution](#7-use-the-solution)
8. [Keep your answers and start over](#8-keep-your-answers-and-start-over)
9. [Do the drills](#9-do-the-drills)
10. [Clean up and resources](#10-clean-up-and-resources)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. The exercises

Do them in order. Each level uses skills from the level before.

| # | Exercise | Services | Time | Starts containers |
| --- | --- | --- | --- | --- |
| 1 | [S3 basics](01-s3-basics/) | S3 | 30–45 min | No |
| 2 | [Messaging](02-messaging/) | SNS, SQS | 45–60 min | No |
| 3 | [Serverless API](03-serverless-api/) | API Gateway, Lambda, DynamoDB, IAM, CloudWatch Logs | 60–90 min | 1 Lambda |
| 4 | [Event-driven](04-event-driven/) | S3, EventBridge, SQS, EventBridge Pipes, Step Functions, Lambda, DynamoDB | 90–120 min | 1 Lambda |
| 5 | [Modules and tests](05-modules-and-tests/) | SQS, OpenTofu modules, `tofu test` | 60–90 min | No |
| 6 | [Containers](06-containers/) | ECR, ECS, IAM, CloudWatch Logs | 60–90 min | ECS tasks and a registry |
| — | [Drills](drills/) | Drift, lost state, broken wiring, renames | 10–20 min each | No |

Do the drills at any time after exercise 2.

---

## 2. Before you start

1. Make sure the lab runs:

   ```bash
   mise run health
   ```

2. Make sure these tools are available:

   | Tool | Used for | Check |
   | --- | --- | --- |
   | `uv` | Part C Python code | `uv --version` |
   | `jq` | The checkers of exercises 03, 04, and 06 | `jq --version` |
   | Docker | Lambda in 03 and 04, ECS in 06 | `docker info --format '{{.MemTotal}}'` |

   Exercise 06 needs about 300 MB of free Docker memory.

3. Make sure the lab provider is downloaded. `floci-lab/.terraform/providers`
   must exist. If it does not, run `tofu init` in `floci-lab/` one time.

---

## 3. How the folder is organized

```
floci-lab/exercises/
├── README.md                 # This guide
├── _lib/check.sh             # Shared checker functions. Do not edit.
├── 01-s3-basics/             # One folder for each exercise
├── 02-messaging/
├── 03-serverless-api/
├── 04-event-driven/
├── 05-modules-and-tests/
├── 06-containers/
└── drills/                   # Short drills on one small stack
```

### Inside an exercise folder

All exercises share the same core files:

```
NN-name/
├── README.md        # The exercise: goal, steps, questions, hints
├── main.tf          # Starter OpenTofu code with TODOs
├── app.py           # Starter Python code with TODOs
├── check.sh         # Checks the result in the emulator
├── provider.tf      # A link to floci-lab/provider.tf. Do not edit.
└── solution/        # The same files, completed
```

Some exercises have more files:

| Exercise | Extra files | What they hold |
| --- | --- | --- |
| 03 | `lambda/handler.py` | The Lambda function code, with TODOs |
| 04 | `lambda/handler.py`, `statemachine.asl.json` | The Lambda code and the Step Functions definition, with TODOs |
| 05 | `modules/queue_with_dlq/`, `tests/queues.tftest.hcl` | The module you write and its tests. There is no `app.py`. |
| 06 | `app/Dockerfile`, `app/index.html` | The container image that you build and push |

### Names

Each exercise uses its own prefix for every resource: `ex01-`, `ex02-`, and so
on. The drills use `drill-`. Exercises do not collide with each other, so you
can leave one running while you start the next.

---

## 4. How an exercise README is organized

Each exercise README has the same sections, in this order:

| Section | What it is for |
| --- | --- |
| Header table | Level, services, and time |
| Goal | The system you build |
| What you learn | The skills the exercise teaches |
| Before you start | The commands to run first |
| Part A — Explore | Build a small version by hand. Watch how the service acts. Part A cleans up after itself. |
| Part B — Build | Complete the TODOs in the starter files. Apply them with OpenTofu. |
| Part C — Use | Complete the TODOs in `app.py`. Run the code against your resources. |
| Check your work | Run the checker |
| Clean up | Destroy the resources |
| Stretch goals | Extra tasks. They have no checker. |
| Hints | Help for known problems. Each hint is closed until you open it. |
| Solution | How to run the finished answer |

Two exercises use other tools in Part A and Part C:

| Exercise | Part A | Part C |
| --- | --- | --- |
| 05 | Explore expressions with `tofu console` | Test the module with `tofu test` |
| All others | Explore with the AWS CLI | Run `app.py` with `uv` |

### Markers in the text

| Marker | Meaning |
| --- | --- |
| **Question:** | Think about the answer before you continue. The README does not give the answer. |
| `> **Note:**` | A place where Floci differs from real AWS, or a fact you need |
| `> **Warning:**` or `> **Caution:**` | Read it before the next step |
| `TODO n` in a file | A task in the starter code. The README tells you when to do it. |

---

## 5. Work through an exercise

This is a full session for exercise 01. The other exercises follow the same
pattern.

1. Go to the exercise folder:

   ```bash
   cd floci-lab/exercises/01-s3-basics
   ```

2. Read the README from the top to the end of Part A.
3. Do Part A. Run the commands one at a time and read each output.
4. Initialize OpenTofu:

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   ```

   The flag reuses the provider that the lab already downloaded. Run this
   command again if you add a `module` block.

5. Open `main.tf`. Complete one TODO, then preview:

   ```bash
   tofu plan
   ```

6. Repeat step 5 for each TODO. Then apply:

   ```bash
   tofu apply
   ```

7. Run the checker. The Part B checks must pass:

   ```bash
   ./check.sh
   ```

8. Open `app.py`. Complete the TODOs, then run the app:

   ```bash
   uv run --with boto3 python app.py
   ```

9. Run the checker again. All checks must pass.
10. Answer the **Question** prompts.
11. Try a stretch goal.
12. Do the Clean up section.

### Steps that change between exercises

| Exercise | Difference |
| --- | --- |
| 03 | Part C needs the API address: `uv run --with boto3 python app.py "$(tofu output -raw invoke_url)"` |
| 04 | Empty the bucket before `tofu destroy`: `aws s3 rm s3://ex04-uploads --recursive` |
| 05 | Part A needs no resources. Part C runs `tofu test`, which makes and deletes its own queues. |
| 06 | Part B applies in two steps. First create the repository, then build and push the image, then apply the rest. |

---

## 6. Use the checker

```bash
./check.sh          # from the exercise folder
../check.sh         # from the solution folder
```

- The checker reads the emulator, not your files. Any correct code passes, also
  when it differs from the solution.
- It prints one `PASS` or `FAIL` line for each check, grouped by part.
- Run it at any time. Before you do Part C, only the Part C checks fail.
- Some checkers send real requests. The 03 and 04 checkers make test data and
  delete it again. The 06 checker sends an HTTP request to your container.

| Exit code | Meaning |
| --- | --- |
| `0` | All checks passed. |
| `1` | One or more checks failed. Read the Hints section. |
| `2` | The checker did not run. The lab environment is not loaded, or the emulator does not answer. |

The checker uses `aws --profile floci` for every call. Without the lab
environment, that profile does not exist, so a checker cannot reach a real AWS
account.

---

## 7. Use the solution

Use the solution after you try, not before. Read the Hints section first.

Compare your code with the solution:

```bash
diff -u main.tf solution/main.tf
diff -u app.py solution/app.py
```

To run the solution:

> **Warning:** Your answer and the solution use the same resource names.
> Destroy your own resources first. If both run, applies fail with "already
> exists" errors.

1. Destroy your resources:

   ```bash
   tofu destroy
   ```

2. Follow the Solution section at the end of the exercise README. It has the
   exact commands for that exercise.

---

## 8. Keep your answers and start over

You complete the TODOs in the starter files. Use Git so you can keep your
answers and still get the original files back.

> **Note:** These are standard Git commands. They need the exercises to be
> committed on `main` first.

### Keep your answers on a practice branch

1. Make a branch before you start:

   ```bash
   git switch -c practice
   ```

2. Commit your work after each exercise:

   ```bash
   git add floci-lab/exercises/01-s3-basics
   git commit -m "practice: exercise 01"
   ```

3. Write your answers to the **Question** prompts in a file, for example
   `floci-lab/exercises/01-s3-basics/NOTES.md`. Commit it with your code.

The `main` branch keeps the original starter files.

### Start one exercise again

1. Destroy the resources of the exercise:

   ```bash
   tofu destroy
   ```

2. Get the starter files back from `main`. Name each file, so that your notes
   stay:

   ```bash
   git restore --source=main -- main.tf app.py
   ```

   Add the extra files of the exercise, for example `lambda/handler.py` for
   exercise 03.

3. Delete the local OpenTofu state, then initialize again:

   ```bash
   rm -f terraform.tfstate terraform.tfstate.backup
   tofu init -plugin-dir=../../.terraform/providers
   ```

---

## 9. Do the drills

The drills are different from the exercises:

| | Exercises | Drills |
| --- | --- | --- |
| Goal | Build a system | Break a working stack and watch OpenTofu react |
| Starter code | TODOs to complete | A complete stack in `main.tf` |
| Checker | `check.sh` | None. You read the output of `tofu plan`. |
| Solution | `solution/` folder | None |

How to use them:

1. Do the Setup section of the [drills README](drills/) one time. It applies
   the stack.
2. Do any drill. Each drill has these parts: Goal, Setup, Steps, What you see,
   Questions, Reset.
3. Do the Reset part at the end of each drill. It returns the stack and
   `main.tf` to the clean state for the next drill.
4. When you finish all drills, run the Clean up section.

---

## 10. Clean up and resources

Destroy each exercise when you finish it. The times below come from a full
test run on this lab.

| Exercise | Apply | Destroy | Left running until destroy |
| --- | --- | --- | --- |
| 01 | about 1 min | under 10 s | Nothing |
| 02 | about 1.5 min | about 2 min | Nothing |
| 03 | under 20 s | under 15 s | 1 Lambda container |
| 04 | about 1 min | about 1.5 min | 1 Lambda container |
| 05 | about 1 min (`tofu test`: about 2.5 min) | about 1.5 min | Nothing |
| 06 | under 1 min | under 10 s | ECS task containers |

- SQS queues and queue policies are slow to create and delete. The provider
  waits for them. This is not a problem with your code.
- After exercise 06, the Floci ECR registry container keeps running, and the
  images you built stay in Docker. Remove the images with
  `docker image rm <image>`.
- `mise run status` lists the containers that run now.
- For an empty emulator, run `mise run reset`. Then delete the old state files:
  `rm -f terraform.tfstate*` in each exercise folder that you used.

---

## 11. Troubleshooting

| Problem | Fix |
| --- | --- |
| `tofu init` cannot find the provider | Run `tofu init` in `floci-lab/` one time. Then run the exercise init again. |
| `Module not installed` | Run `tofu init -plugin-dir=../../.terraform/providers` again. Each new `module` block needs it. |
| `check.sh` exits with `2` | Run it from a folder inside the lab, in a shell where mise is active. Run `mise run up` if the emulator is stopped. |
| A check fails, but the resource exists | Read the check name. It often checks a setting, for example a timeout value or a policy. Then read the Hints section. |
| An apply fails with "already exists" | Your answer and the solution both ran, or an old state file is missing. Destroy the other copy, or import the resource. |
| `tofu destroy` does not end on an S3 bucket | Empty the bucket with `aws s3 rm s3://<bucket> --recursive`. Then destroy again. |
| `uv` downloads packages each run | This is normal on the first run. Later runs use the cache. |
| The Mac is slow | Run `mise run status`. Destroy the exercises that you do not use. |
