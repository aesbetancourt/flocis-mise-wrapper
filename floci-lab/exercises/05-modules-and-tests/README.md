# Exercise 05 — Modules and tests

| Level | Services | Time |
| --- | --- | --- |
| 5 | SQS | 60–90 minutes |

## Goal

Package a queue and its dead-letter queue as a reusable module. Create three
queues from one map with `for_each`. Then prove that the module works with
`tofu test`.

## What you learn

- How to write a module: inputs, resources, and outputs.
- How a validation rule stops a bad input before any AWS call.
- How `for_each` makes one module instance for each map entry.
- How `tofu test` runs plan and apply checks, then deletes what it made.
- Why some values are unknown at plan time, and how `override_resource` helps.

## Before you start

1. Make sure the lab runs:

   ```bash
   mise run health
   ```

2. Go to this folder:

   ```bash
   cd floci-lab/exercises/05-modules-and-tests
   ```

3. Initialize OpenTofu. The flag reuses the provider that the lab already
   downloaded:

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   ```

---

## Part A — Explore with tofu console

Learn the expressions that the module uses before you write it. The console
reads the `locals` block in `main.tf`.

1. Open the console:

   ```bash
   tofu console
   ```

2. Read the queue map and one value:

   ```hcl
   local.queues
   local.queues["ex05-orders"].max_receive_count
   ```

   The second line shows `5`.

3. Make the dead-letter queue names with a `for` expression:

   ```hcl
   { for name, cfg in local.queues : "${name}-dlq" => cfg.max_receive_count }
   ```

   **Question:** The map in `main.tf` lists `ex05-orders` first. Why does the
   result start with `ex05-emails`?

4. Make a redrive policy:

   ```hcl
   jsonencode({ deadLetterTargetArn = "arn:aws:sqs:us-east-1:000000000000:ex05-orders-dlq", maxReceiveCount = 5 })
   ```

   The result is a string, not an object. SQS stores the redrive policy as a
   JSON string.

5. Turn a JSON string back into an object:

   ```hcl
   jsondecode("{\"maxReceiveCount\":5}")
   ```

   You use `jsondecode` again in the tests in Part C.

6. Try the rule that the module validation uses, with the value `0`:

   ```hcl
   0 >= 1 && 0 <= 10
   ```

   The result is `false`. A validation rule with a `false` result stops the
   plan.

7. Close the console:

   ```hcl
   exit
   ```

---

## Part B — Build with OpenTofu

1. Open `modules/queue_with_dlq/variables.tf`. Complete TODO 1 to TODO 4.
2. Open `modules/queue_with_dlq/main.tf`. Complete TODO 5 to TODO 7.
3. Open `modules/queue_with_dlq/outputs.tf`. Complete TODO 8.
4. Open `main.tf`. Complete TODO 9 and TODO 10.
5. Install the module. OpenTofu must install each new module block before a
   plan:

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   ```

6. Preview the changes:

   ```bash
   tofu plan
   ```

   The plan must show `Plan: 6 to add`.

7. Apply the changes:

   ```bash
   tofu apply
   ```

   Each queue takes about 25 seconds. The provider reads the queue every 5
   seconds until the attributes are stable. The three dead-letter queues come
   first, because each main queue needs the ARN of its dead-letter queue.

8. Read the output:

   ```bash
   tofu output queue_urls
   ```

9. Run `tofu plan` again. It must show `No changes`.

10. List the resources in the state, then show one of them:

    ```bash
    tofu state list
    tofu state show 'module.queues["ex05-reports"].aws_sqs_queue.main'
    ```

    **Question:** Which part of the address tells you the module instance?

11. Open `tofu console` and read one module instance:

    ```hcl
    module.queues["ex05-orders"]
    module.queues["ex05-orders"].aws_sqs_queue.main
    ```

    The first line shows the four outputs. The second line fails with
    `Unsupported attribute`. **Question:** Why can the root module read only
    the outputs of a module?

12. Prove that the redrive policy works. `ex05-reports` moves a message after
    one receive. The flag `--visibility-timeout 1` makes the message visible
    again after one second:

    ```bash
    Q=$(aws sqs get-queue-url --queue-name ex05-reports --query QueueUrl --output text)
    aws sqs send-message --queue-url "$Q" --message-body "report 1"
    aws sqs receive-message --queue-url "$Q" --visibility-timeout 1 --query 'Messages[].Body' --output text
    sleep 2
    aws sqs receive-message --queue-url "$Q" --visibility-timeout 1 --query 'Messages[].Body' --output text
    aws sqs receive-message --queue-url "$Q-dlq" --query 'Messages[].Body' --output text
    ```

    The first receive shows `report 1`. The second receive shows `None`. The
    receive from the dead-letter queue shows `report 1`.

13. Test the validation rule. In `main.tf`, set `max_receive_count = 0` for
    `ex05-reports`, then run `tofu plan`. The plan fails with
    `Invalid value for variable` and your error message. Set the value back
    to `1`.

---

## Part C — Test it with tofu test

A test file has `run` blocks. Each `run` block makes a plan or an apply, then
checks `assert` conditions. The runs in this exercise test the module
directly, with the names `ex05-test-*`. Your `ex05-` queues from Part B are
not part of the test.

1. Open `tests/queues.tftest.hcl`. Complete TODO 11.
2. Install the module for the new `run` block:

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   ```

   Do this each time you add or rename a `run` block with a `module` block.

3. Run the test:

   ```bash
   tofu test
   ```

   The redrive assertion fails with `Unknown condition run`. **Question:** The
   plan knows the queue names. Why does it not know the redrive policy? Read
   the hint "Unknown condition run". Fix the run, then run `tofu test` again.

4. Complete TODO 12 and TODO 13. Run `tofu init` again, then run the test:

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   tofu test
   ```

   The test takes about 2 minutes. The last line must show
   `Success! 3 passed, 0 failed.`

5. Run the test again. While it runs, list the test queues in a second
   terminal:

   ```bash
   aws sqs list-queues --queue-name-prefix ex05-test
   ```

   Run the command again after the test ends. The list is empty.
   **Question:** You did not run `tofu destroy`. Which command deleted the
   test queues?

---

## Check your work

```bash
./check.sh
```

The checker reads the emulator, not your files. Run it after Part B. All checks
must show `PASS`.

---

## Clean up

1. Destroy the resources:

   ```bash
   tofu destroy
   ```

2. Run `./check.sh` again. All checks must show `FAIL`.

---

## Stretch goals

- Rename the module block from `queues` to `sqs_queues`. Add a `moved` block
  from `module.queues` to `module.sqs_queues`. Run `tofu init` again, because
  the module has a new name. The plan must show `has moved to` and no destroy.
- Add the queue `ex05-billing` as a separate module block and apply. Then move
  it into `local.queues`. Add a `moved` block from `module.billing` to
  `module.queues["ex05-billing"]`. The plan must show `has moved to`.
- Add a second test file that tests the root module with
  `mock_provider "aws" {}`. It runs without the emulator, in a few seconds.
- Add an `aws_sqs_queue_redrive_allow_policy` to the dead-letter queue. Use
  `redrivePermission = "byQueue"` and the ARN of the main queue.

  > **Note:** Floci stores this policy but does not enforce it. Another queue
  > can still use the dead-letter queue and move messages to it. On real AWS,
  > only the queues in `sourceQueueArns` can use it.

---

## Hints

<details>
<summary>tofu plan fails with "Module not installed"</summary>

A new `module` block needs `tofu init`. Run the init command again, with the
`-plugin-dir` flag:

```bash
tofu init -plugin-dir=../../.terraform/providers
```

A new `run` block with a `module` block in a test file needs the same command.

</details>

<details>
<summary>TODO 7: the format of the redrive policy</summary>

```hcl
redrive_policy = jsonencode({
  deadLetterTargetArn = aws_sqs_queue.dlq.arn
  maxReceiveCount     = var.max_receive_count
})
```

</details>

<details>
<summary>TODO 9: which values come from each</summary>

`each.key` is the queue name, for example `ex05-orders`. `each.value` is the
object for that name. Use `each.value.max_receive_count` and
`each.value.visibility_timeout_seconds`.

</details>

<details>
<summary>tofu test: "Unknown condition run"</summary>

In a plan, the ARN of the new dead-letter queue is `(known after apply)`. The
redrive policy contains that ARN, so the whole policy string is unknown.

Give the dead-letter queue a fixed ARN for this run only:

```hcl
override_resource {
  target = aws_sqs_queue.dlq
  values = {
    arn = "arn:aws:sqs:us-east-1:000000000000:ex05-test-jobs-dlq"
  }
}
```

The override applies only to the run that contains it.

</details>

<details>
<summary>tofu test: the other runs show "skip"</summary>

A run that stops with an error, for example `Unknown condition run` or
`Missing expected failure`, skips the next runs in the file. A failed
`assert` does not skip them. Fix the first run that failed.

</details>

<details>
<summary>tofu test: I stopped the test with Ctrl+C</summary>

OpenTofu shows `Interrupt received`. It completes the current run, skips the
next runs, and then deletes the test queues. Wait for the command to end. Then
make sure that no test queue is left:

```bash
aws sqs list-queues --queue-name-prefix ex05-test
```

</details>

<details>
<summary>tofu test: "Missing expected failure"</summary>

The plan accepted `max_receive_count = 0`. Make sure the validation block in
`variables.tf` rejects values below 1.

</details>

<details>
<summary>check.sh: "has maxReceiveCount" fails</summary>

Compare `local.queues` in `main.tf` with the table in the checker:
`ex05-orders` 5, `ex05-emails` 3, `ex05-reports` 1. Make sure the module call
passes `each.value.max_receive_count`, not a fixed number.

</details>

---

## Solution

Try the exercise first. The solution is in [`solution/`](solution/).

To run the solution, destroy your own resources first. Both use the same queue
names.

```bash
cd solution
tofu init -plugin-dir=../../../.terraform/providers
tofu apply
../check.sh
tofu test
tofu destroy
```
