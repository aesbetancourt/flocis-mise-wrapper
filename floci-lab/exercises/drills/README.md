# Drills

Short drills that break a small stack on purpose. Each drill shows how OpenTofu
reacts when the code, the state, and the emulator do not agree. Do them at any
level.

| Drill | You break | You learn | Time |
| --- | --- | --- | --- |
| [1. Drift](#drill-1--drift) | A queue, a tag, and a parameter, with the CLI | How `plan` finds changes made outside the code | 10 minutes |
| [2. Lost state](#drill-2--lost-state) | The state file | What state is, and how `import` rebuilds it | 20 minutes |
| [3. Broken wiring](#drill-3--broken-wiring) | The queue ARN of a subscription | Why references are safer than strings | 10 minutes |
| [4. Rename](#drill-4--rename) | The name of a resource block | Why a rename destroys data, and how `moved` stops it | 15 minutes |

## The stack

`main.tf` makes these resources. All drills use them.

| Resource | Name |
| --- | --- |
| `aws_sqs_queue.orders` | `drill-orders` |
| `aws_sns_topic.events` | `drill-events` |
| `aws_sqs_queue_policy.orders` | Lets `drill-events` send to `drill-orders` |
| `aws_sns_topic_subscription.orders` | Sends each message from the topic to the queue |
| `aws_s3_bucket.files` | `drill-files` |
| `aws_ssm_parameter.greeting` | `drill-greeting`, value `hello` |

## Setup

Do these steps one time, before the first drill.

1. Make sure the lab runs:

   ```bash
   mise run health
   ```

2. Go to this folder:

   ```bash
   cd floci-lab/exercises/drills
   ```

3. Initialize OpenTofu:

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   ```

4. Apply the stack:

   ```bash
   tofu apply
   ```

   The apply takes about one minute. The queue and the queue policy take about
   25 seconds each. The provider reads them every 5 seconds until they are
   stable.

5. Save the queue URL and the topic ARN in your shell. The drills use them:

   ```bash
   Q=$(tofu output -raw queue_url)
   T=$(tofu output -raw topic_arn)
   ```

   Run this step again when you open a new terminal.

6. Make sure the wiring works:

   ```bash
   aws sns publish --topic-arn "$T" --message "order 1"
   aws sqs receive-message --queue-url "$Q" --wait-time-seconds 5 --query 'Messages[].Body' --output text
   aws sqs purge-queue --queue-url "$Q"
   ```

   The receive shows `order 1`. The purge empties the queue for the next drill.

Each drill ends with a **Reset** step. After the reset, `tofu plan` must show
`No changes`.

---

## Drill 1 — Drift

### Goal

Change resources with the AWS CLI, outside OpenTofu. Read how `tofu plan`
reports the difference. Then choose: undo the change, or keep it.

Docs: [plan modes](https://opentofu.org/docs/cli/commands/plan/),
[refresh-only](https://opentofu.org/docs/cli/commands/refresh/).

### Setup

The stack is applied, and `tofu plan` shows `No changes`.

### Steps

1. Change three things with the CLI:

   ```bash
   aws sqs set-queue-attributes --queue-url "$Q" --attributes VisibilityTimeout=90
   aws sqs tag-queue --queue-url "$Q" --tags team=cli
   aws ssm put-parameter --name drill-greeting --value "hello from the CLI" --overwrite
   ```

2. Preview the changes:

   ```bash
   tofu plan
   ```

3. Show only what changed outside OpenTofu:

   ```bash
   tofu plan -refresh-only
   ```

4. Record the changes in the state. Type `yes` at the prompt:

   ```bash
   tofu apply -refresh-only
   ```

5. Run `tofu plan` again.
6. Choose one way to go on:
   - **Keep the changes.** In `main.tf`, set `visibility_timeout_seconds = 90`,
     add the tag `team = "cli"`, and set the value `"hello from the CLI"`. Run
     `tofu plan`.
   - **Undo the changes.** Go to the Reset step.

### What you see

- Step 2 shows `Plan: 0 to add, 2 to change, 0 to destroy.` The queue shows
  `visibility_timeout_seconds = 90 -> 30` and `- "team" = "cli" -> null`. The
  parameter shows `value = (sensitive value)` and
  `version = 2 -> (known after apply)`.
- Step 3 starts with `Note: Objects have changed outside of OpenTofu`. The
  arrows point the other way: `visibility_timeout_seconds = 30 -> 90` and
  `version = 1 -> 2`. The list also shows changes that you did not make:
  `+ tags = {}` on the bucket, the topic, and the parameter, and
  `+ policy = jsonencode(...)` on the queue.
- Step 4 shows `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`
  Nothing changes in the emulator.
- Step 5 shows the same `2 to change` as step 2.
- When you keep the changes, `tofu plan` shows `No changes`.

### Questions

- In step 2, each arrow goes from the value in the emulator to the value in
  the code. What does `tofu apply` do to the queue?
- Why does the aws provider hide the old and the new parameter value?
- In step 3, why does the queue show a `policy` that is not in its resource
  block? Which resource sets it?
- After step 4, the state has the new values. Why does step 5 still plan a
  change?

### Reset

1. Undo your edits in `main.tf`, if you made some.
2. Apply the code. Type `yes` at the prompt:

   ```bash
   tofu apply
   ```

   The apply changes the queue and the parameter back.

3. Make sure the queue is back to 30 seconds:

   ```bash
   aws sqs get-queue-attributes --queue-url "$Q" --attribute-names VisibilityTimeout --output text
   ```

   The output shows `ATTRIBUTES	30`.

4. Run `tofu plan`. It must show `No changes`.

---

## Drill 2 — Lost state

### Goal

Lose the state file. See why OpenTofu then wants to create resources that
exist. Rebuild the state with `import` blocks and with `tofu import`.

Docs: [state](https://opentofu.org/docs/language/state/),
[import blocks](https://opentofu.org/docs/language/import/),
[generate code](https://opentofu.org/docs/language/import/generating-configuration/),
[tofu import](https://opentofu.org/docs/cli/commands/import/).

### Setup

The stack is applied, and `tofu plan` shows `No changes`.

### Steps

1. List the resources in the state:

   ```bash
   tofu state list
   ```

2. Move the state files away:

   ```bash
   mkdir -p lost
   mv terraform.tfstate* lost/
   ```

3. Preview the changes:

   ```bash
   tofu plan
   ```

4. Predict which creates fail. Then apply. Type `yes` at the prompt:

   ```bash
   tofu apply
   ```

5. List the state again, and the subscriptions of the topic:

   ```bash
   tofu state list
   aws sns list-subscriptions-by-topic --topic-arn "$T" --query 'Subscriptions[].SubscriptionArn' --output text
   ```

6. Import the two missing resources. Make the file `imports.tf`:

   ```hcl
   import {
     to = aws_s3_bucket.files
     id = "drill-files"
   }

   import {
     to = aws_ssm_parameter.greeting
     id = "drill-greeting"
   }
   ```

7. Preview and apply the import:

   ```bash
   tofu plan
   tofu apply
   ```

8. Run `tofu plan` again. It must show `No changes`.
9. Try the import command. Remove the parameter from the state, then import it
   again:

   ```bash
   tofu state rm aws_ssm_parameter.greeting
   tofu import aws_ssm_parameter.greeting drill-greeting
   tofu plan
   ```

10. Import a resource that has no code. Make a parameter with the CLI:

    ```bash
    aws ssm put-parameter --name drill-legacy --type String --value "made by hand"
    ```

11. Replace the content of `imports.tf` with this block:

    ```hcl
    import {
      to = aws_ssm_parameter.legacy
      id = "drill-legacy"
    }
    ```

12. Let OpenTofu write the code:

    ```bash
    tofu plan -generate-config-out=generated.tf
    ```

13. Open `generated.tf`. Delete the line `tier = ""`. Change
    `value = null # sensitive` to `value = "made by hand"`. Then preview and
    apply:

    ```bash
    tofu plan
    tofu apply
    ```

### What you see

- Step 1 shows six resources.
- Step 3 shows `Plan: 6 to add, 0 to change, 0 to destroy.`
- In step 4, the queue, the topic, the subscription, and the queue policy show
  `Creation complete`. Two creates fail:
  - `Error: creating S3 Bucket (drill-files): BucketAlreadyExists`
  - `Error: creating SSM Parameter (drill-greeting): ... ParameterAlreadyExists`
- Step 5 shows four resources in the state. The topic still has one
  subscription, with the same ARN as before.
- Step 7 shows `Plan: 2 to import, 0 to add, 1 to change, 0 to destroy.` The
  bucket shows `force_destroy = false -> true`. The apply shows
  `Apply complete! Resources: 2 imported, 0 added, 1 changed, 0 destroyed.`
- Step 9 shows `Import successful!`, then `No changes`. The command
  `tofu state rm` also makes a file `terraform.tfstate.<number>.backup`.
- Step 12 fails with `Planning failed`. The errors include
  `expected tier to be one of ["Standard" "Advanced" "Intelligent-Tiering"], got`
  and ``"value": one of `insecure_value,value,value_wo` must be specified``. The file
  `generated.tf` exists anyway.
- Step 13 shows `Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.`

> **Note:** Floci returns the existing queue, topic, or subscription when you
> create one with the same name and settings. On real AWS, `CreateQueue` and
> `CreateTopic` also return the existing resource in this case. The bucket
> error does not come from the emulator. The provider sends a `HEAD` request
> for the name first, and stops when the bucket exists.

> **Note:** On Floci, an import of `aws_sqs_queue` or `aws_sqs_queue_policy`
> with the queue URL `http://localhost:4566/000000000000/drill-orders` fails
> with `could not parse ... as SQS URL`. Use the AWS form of the URL, for
> example `https://sqs.us-east-1.amazonaws.com/000000000000/drill-orders`. The
> import then works, but the state keeps that URL.

> **Note:** Floci returns an empty tier and the ARN
> `arn:aws:ssm:us-east-1:000000000000:parameterdrill-legacy`, without a `/`.
> Real AWS returns the tier `Standard` and a `/` after `parameter`.

### Questions

- In step 3, the resources exist. Why does OpenTofu plan to create them?
- In step 4, four creates "worked". Why is this more dangerous than an error?
- Why does the bucket import change `force_destroy`? Where does S3 store that
  setting?
- On a real incident, which is safer: import first, or apply first?
- Why can the generated code not contain the parameter value?

### Reset

1. Delete the files that the drill made:

   ```bash
   rm -rf imports.tf generated.tf lost
   rm -f terraform.tfstate.*.backup
   ```

   In zsh, the second command shows `no matches found` when step 9 made no
   backup file. You can ignore this message.

2. Apply the code. Type `yes` at the prompt:

   ```bash
   tofu apply
   ```

   The plan shows `aws_ssm_parameter.legacy will be destroyed`. The apply
   deletes `drill-legacy`, because no code describes it now.

3. Run `tofu plan`. It must show `No changes`.

---

## Drill 3 — Broken wiring

### Goal

Give the subscription a wrong queue ARN. Predict the plan, apply it, and find
out why no message arrives.

Docs: [references](https://opentofu.org/docs/language/expressions/references/),
[SNS to SQS](https://docs.aws.amazon.com/sns/latest/dg/subscribe-sqs-queue-to-sns-topic.html).

### Setup

The stack is applied, `tofu plan` shows `No changes`, and the queue is empty.

### Steps

1. In `main.tf`, find the subscription. Change the endpoint to a reference with
   a typo:

   ```hcl
   endpoint             = aws_sqs_queue.ordres.arn
   ```

2. Run `tofu plan`.
3. Now use a string with the same typo:

   ```hcl
   endpoint             = "arn:aws:sqs:us-east-1:000000000000:drill-ordres"
   ```

4. Predict the plan. Then run `tofu plan`.
5. Apply the change. Type `yes` at the prompt:

   ```bash
   tofu apply
   ```

6. Publish a message and try to receive it:

   ```bash
   aws sns publish --topic-arn "$T" --message "order 2"
   aws sqs receive-message --queue-url "$Q" --wait-time-seconds 5 --query 'Messages[].Body' --output text
   ```

7. Find the cause. Read the endpoint of the subscription, then look for that
   queue:

   ```bash
   aws sns list-subscriptions-by-topic --topic-arn "$T" --query 'Subscriptions[].Endpoint' --output text
   aws sqs get-queue-url --queue-name drill-ordres
   ```

8. Read the emulator log. In a second terminal, go to the lab folder and run:

   ```bash
   mise run logs
   ```

   In the first terminal, publish `order 3`. In the log, look for
   `drill-ordres`. Then stop the log with Ctrl+C.

### What you see

- Step 2 fails with `Error: Reference to undeclared resource`. Nothing reaches
  the emulator.
- Step 4 shows `aws_sns_topic_subscription.orders must be replaced` and
  `endpoint ... -> "arn:aws:sqs:us-east-1:000000000000:drill-ordres" # forces replacement`.
  The summary is `Plan: 1 to add, 0 to change, 1 to destroy.`
- Step 5 shows `Apply complete! Resources: 1 added, 0 changed, 1 destroyed.`
- In step 6, the publish returns a message ID. The receive shows `None`.
- Step 7 shows the endpoint `arn:aws:sqs:us-east-1:000000000000:drill-ordres`.
  The queue lookup fails with `AWS.SimpleQueueService.NonExistentQueue`.
- Step 8 shows this line for each publish:
  `WARN ... Failed to deliver SNS message to arn:aws:sqs:us-east-1:000000000000:drill-ordres: The specified queue does not exist.`

> **Note:** Floci accepts a subscription to a queue that does not exist, and
> the publish still succeeds. Only the emulator log shows the failure. On real
> AWS, look for failed deliveries in the CloudWatch metric
> `NumberOfNotificationsFailed` of the topic.

### Questions

- Why does a typo in a reference fail at plan, but a typo in a string does not?
- Why must OpenTofu replace the subscription, not update it?
- The publish succeeded. Which part of the system lost the message?

### Reset

1. In `main.tf`, set the endpoint back to the reference:

   ```hcl
   endpoint             = aws_sqs_queue.orders.arn
   ```

2. Apply the change. Type `yes` at the prompt:

   ```bash
   tofu apply
   ```

   The subscription is replaced again.

3. Publish a message and receive it:

   ```bash
   aws sns publish --topic-arn "$T" --message "order 4"
   aws sqs receive-message --queue-url "$Q" --wait-time-seconds 5 --query 'Messages[].Body' --output text
   aws sqs purge-queue --queue-url "$Q"
   ```

   The receive shows only `order 4`. The messages from the broken wiring do not
   arrive later.

4. Run `tofu plan`. It must show `No changes`.

---

## Drill 4 — Rename

### Goal

Rename the queue resource block. See why the plan destroys the queue, and how a
`moved` block keeps it. Then see what a replacement does to the messages in the
queue.

Docs: [refactoring with moved](https://opentofu.org/docs/language/modules/develop/refactoring/),
[plan -replace](https://opentofu.org/docs/cli/commands/plan/),
[DeleteQueue](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_DeleteQueue.html).

### Setup

The stack is applied, `tofu plan` shows `No changes`, and the queue is empty.

### Steps

1. Put one message in the queue, then count the messages:

   ```bash
   aws sqs send-message --queue-url "$Q" --message-body "keep me"
   aws sqs get-queue-attributes --queue-url "$Q" --attribute-names ApproximateNumberOfMessages --output text
   ```

2. Rename the block `aws_sqs_queue.orders` to `aws_sqs_queue.jobs`. Change the
   label and the four references. You can use this command:

   ```bash
   sed -i '' -e 's/"aws_sqs_queue" "orders"/"aws_sqs_queue" "jobs"/' \
     -e 's/aws_sqs_queue\.orders\./aws_sqs_queue.jobs./g' main.tf
   ```

3. Run `tofu plan`. Do not apply.
4. Add a `moved` block at the end of `main.tf`:

   ```hcl
   moved {
     from = aws_sqs_queue.orders
     to   = aws_sqs_queue.jobs
   }
   ```

5. Run `tofu plan`, then apply. Type `yes` at the prompt:

   ```bash
   tofu plan
   tofu apply
   ```

6. Count the messages again, and list the state:

   ```bash
   aws sqs get-queue-attributes --queue-url "$Q" --attribute-names ApproximateNumberOfMessages --output text
   tofu state list
   ```

7. Replace the queue on purpose. Type `yes` at the prompt:

   ```bash
   tofu apply -replace=aws_sqs_queue.jobs
   ```

8. Count the messages again:

   ```bash
   aws sqs get-queue-attributes --queue-url "$Q" --attribute-names ApproximateNumberOfMessages --output text
   ```

### What you see

- Step 1 shows `ATTRIBUTES	1`.
- Step 3 shows `aws_sqs_queue.orders will be destroyed`,
  `(because aws_sqs_queue.orders is not in configuration)`, and
  `aws_sqs_queue.jobs will be created`. The queue policy and the subscription
  show `must be replaced`. The summary is
  `Plan: 3 to add, 0 to change, 3 to destroy.`
- Step 5 shows `# aws_sqs_queue.orders has moved to aws_sqs_queue.jobs` and
  `Plan: 0 to add, 0 to change, 0 to destroy.`
- Step 6 shows `ATTRIBUTES	1`. The state lists `aws_sqs_queue.jobs`.
- Step 7 shows `aws_sqs_queue.jobs will be replaced, as requested` and
  `Plan: 3 to add, 0 to change, 3 to destroy.` OpenTofu deletes the
  subscription, the policy, and the queue first. Then it creates them again.
  The apply takes about 2 minutes.
- Step 8 shows `ATTRIBUTES	0`. The message is gone.

### Questions

- The queue name did not change. Why does the plan in step 3 destroy the queue?
- Why must the queue policy and the subscription also be replaced?
- After step 5, you can delete the `moved` block and `tofu plan` shows
  `No changes`. Why? When must you keep a `moved` block?

### Reset

Choose one way.

**Fast reset (about 1 minute)**

1. Rename the block back to `orders`:

   ```bash
   sed -i '' -e 's/"aws_sqs_queue" "jobs"/"aws_sqs_queue" "orders"/' \
     -e 's/aws_sqs_queue\.jobs\./aws_sqs_queue.orders./g' main.tf
   ```

2. Change the `moved` block to `from = aws_sqs_queue.jobs` and
   `to = aws_sqs_queue.orders`.
3. Apply. Type `yes` at the prompt:

   ```bash
   tofu apply
   ```

4. Delete the `moved` block.
5. Run `tofu plan`. It must show `No changes`.

**Rename without a moved block (about 4 minutes)**

This way shows what goes wrong when a rename has no `moved` block.

> **Caution:** This apply ends with an error. The state then has two addresses
> for the same queue URL. Do not apply again before step 4 repairs the state.

1. Rename the block back to `orders` with the `sed` command of the fast reset.
2. Delete the `moved` block.
3. Apply. Type `yes` at the prompt:

   ```bash
   tofu apply
   ```

   OpenTofu deletes `aws_sqs_queue.jobs` and creates `aws_sqs_queue.orders` at
   the same time. Both have the name `drill-orders`. The create completes. The
   delete waits for `drill-orders` to go away, but the new queue has the same
   URL. After 3 minutes, the apply fails with
   `Error: waiting for SQS Queue (http://localhost:4566/000000000000/drill-orders) delete: timeout while waiting for resource to be gone`.
   The queue policy and the subscription are not created. `tofu plan` now
   shows `aws_sqs_queue.jobs will be destroyed`, but that address points to the
   URL of the new queue.

4. Repair the state. Remove the old address, then apply again:

   ```bash
   tofu state rm aws_sqs_queue.jobs
   tofu apply
   ```

   The plan shows `Plan: 2 to add, 0 to change, 0 to destroy.`

5. Delete the backup file of `tofu state rm`:

   ```bash
   rm -f terraform.tfstate.*.backup
   ```

6. Run `tofu plan`. It must show `No changes`.

> **Note:** Floci creates a queue with the same name right after it deletes
> one. Real AWS requires a wait of at least 60 seconds after `DeleteQueue`
> before you create a queue with the same name.

---

## Clean up

When you finish all drills, destroy the stack:

```bash
tofu destroy
```
