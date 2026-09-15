# Exercise 02 — Messaging

| Level | Services | Time |
| --- | --- | --- |
| 2 | SNS, SQS | 45–60 minutes |

## Goal

Build an order topic that sends each order to a billing queue and a shipping
queue. A billing message that fails two times moves to a dead-letter queue
(DLQ). Then publish, consume, and fail orders from code.

## What you learn

- Fan-out: one SNS publish puts a copy of the message in each subscribed queue.
- The SNS envelope, and how raw message delivery removes it.
- Queue policies that let a topic send messages to a queue.
- Visibility timeout, receive count, and the redrive policy.
- Resource wiring: one resource uses the ARN of another resource.

## Before you start

1. Make sure the lab runs:

   ```bash
   mise run health
   ```

2. Go to this folder:

   ```bash
   cd floci-lab/exercises/02-messaging
   ```

---

## Part A — Explore with the AWS CLI

See fan-out and the SNS envelope before you write code. The steps keep ARNs
and URLs in shell variables. Run all the steps in the same terminal.

1. Create a topic:

   ```bash
   TOPIC_ARN=$(aws sns create-topic --name ex02-cli-news --query TopicArn --output text)
   echo "$TOPIC_ARN"
   ```

2. Create two queues:

   ```bash
   PLAIN_URL=$(aws sqs create-queue --queue-name ex02-cli-plain --query QueueUrl --output text)
   RAW_URL=$(aws sqs create-queue --queue-name ex02-cli-raw --query QueueUrl --output text)
   ```

3. Read the queue ARNs. A subscription uses the queue ARN, not the queue URL:

   ```bash
   PLAIN_ARN=$(aws sqs get-queue-attributes --queue-url "$PLAIN_URL" \
     --attribute-names QueueArn --query Attributes.QueueArn --output text)
   RAW_ARN=$(aws sqs get-queue-attributes --queue-url "$RAW_URL" \
     --attribute-names QueueArn --query Attributes.QueueArn --output text)
   ```

4. Subscribe both queues to the topic. Turn on raw message delivery for the
   second queue only:

   ```bash
   aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs \
     --notification-endpoint "$PLAIN_ARN"
   aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs \
     --notification-endpoint "$RAW_ARN" --attributes RawMessageDelivery=true
   ```

5. List the subscriptions of the topic:

   ```bash
   aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
     --query 'Subscriptions[].[Endpoint,Protocol]' --output table
   ```

6. Publish one message to the topic:

   ```bash
   aws sns publish --topic-arn "$TOPIC_ARN" --subject "Test" --message "Hello, queues!"
   ```

7. Receive the message from each queue:

   ```bash
   aws sqs receive-message --queue-url "$PLAIN_URL" --wait-time-seconds 5 \
     --query 'Messages[0].Body' --output text
   aws sqs receive-message --queue-url "$RAW_URL" --wait-time-seconds 5 \
     --query 'Messages[0].Body' --output text
   ```

   The first body is a JSON envelope. The second body is only `Hello, queues!`.

   **Question:** You published one time. Why does each queue have a message?
   Which fields does the envelope add to your text?

   > **Note:** On Floci, the envelope has `Type`, `MessageId`, `TopicArn`,
   > `Timestamp`, `Subject`, `Message`, and `MessageAttributes`. On real AWS,
   > the envelope also has `SignatureVersion`, `Signature`, `SigningCertURL`,
   > and `UnsubscribeURL`.

   > **Note:** You did not create a queue policy, but Floci delivered the
   > messages. On real AWS, SNS cannot send to a queue without a queue policy
   > that allows it. The messages do not arrive. Part B adds the queue policies.

8. Delete the topic and the queues. When you delete a topic, its subscriptions
   are also deleted:

   ```bash
   aws sns delete-topic --topic-arn "$TOPIC_ARN"
   aws sqs delete-queue --queue-url "$PLAIN_URL"
   aws sqs delete-queue --queue-url "$RAW_URL"
   ```

---

## Part B — Build with OpenTofu

1. Initialize OpenTofu. The flag reuses the provider that the lab already
   downloaded:

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   ```

2. Open `main.tf`. Complete TODO 1 to TODO 6.
3. Preview the changes after each TODO:

   ```bash
   tofu plan
   ```

4. Apply the changes. Each queue and each queue policy takes about 25 seconds
   to create:

   ```bash
   tofu apply
   ```

   **Question:** Read the apply output. Which queue does OpenTofu create before
   `ex02-billing`? Why?

5. Read the outputs:

   ```bash
   tofu output
   ```

6. Run `tofu plan` again. It must show `No changes`.

---

## Part C — Use it from code

1. Open `app.py`. Complete TODO 1 to TODO 4.
2. Run the app:

   ```bash
   uv run --with boto3 python app.py
   ```

   The app runs for about 15 seconds. The output of the solution is:

   ```text
   Published order 1001. Message ID: <id>
   Shipping: envelope type Notification. Order 1001 is shipped.
   Billing: receive 1, receive count 1. Payment failed. Message not deleted.
   Billing: receive 2, receive count 2. Payment failed. Message not deleted.
   Billing: the last receive returned no message.
   Dead-letter queue: 1 message(s).
     {"order_id": "1001", "item": "book", "quantity": 1}
   ```

   Your output can use different words. It must show two billing receives and
   the order in the dead-letter queue.

3. **Question:** Billing received the message two times. Then a receive
   returned no message. Where is the message now? Which setting sets the number
   2?

4. **Question:** Shipping reads the order from the `Message` field of the body.
   The DLQ body is the order itself. Which setting makes this difference?

5. Run the app a second time. **Question:** How many messages are in the
   dead-letter queue now? Why are the old messages still there?

---

## Check your work

```bash
./check.sh
```

The checker reads the emulator, not your files. All checks must show `PASS`.

---

## Clean up

1. Destroy the resources:

   ```bash
   tofu destroy
   ```

2. **Question:** The dead-letter queue still held messages, but the destroy
   did not fail. In exercise 01, a bucket with objects made the destroy fail.
   What is different?

---

## Stretch goals

- Add a filter policy to the shipping subscription. Shipping must get only
  orders with the message attribute `type` set to `physical`. In `app.py`,
  publish one `physical` and one `digital` order. Use `filter_policy` and
  `MessageAttributes`.
- Add an `aws_sqs_queue_redrive_allow_policy` to the DLQ. Allow only
  `ex02-billing` to use it as a dead-letter queue.
- Move the messages from the DLQ back to `ex02-billing`. Use
  `aws sqs start-message-move-task --source-arn <dlq-arn>`. Then read the task
  status with `aws sqs list-message-move-tasks --source-arn <dlq-arn>`.
- In `app.py`, publish three orders in one call with `publish_batch`. Change
  the billing loop so that it handles more than one message.

---

## Hints

<details>
<summary>tofu init fails: the provider is not in the plugin directory</summary>

The lab provider is not downloaded yet. Run `tofu init` in `floci-lab/` once,
or run `mise run install`. Then run the init command of this exercise again.

</details>

<details>
<summary>TODO 3: "Inappropriate value for attribute "redrive_policy": string required"</summary>

The redrive policy is a JSON string, not an HCL map. Use `jsonencode()` with
the keys `deadLetterTargetArn` and `maxReceiveCount`:

```hcl
redrive_policy = jsonencode({
  deadLetterTargetArn = aws_sqs_queue.<dlq>.arn
  maxReceiveCount     = 2
})
```

</details>

<details>
<summary>TODO 4: how to write the queue policy</summary>

Write one `statement` in an `aws_iam_policy_document` data source:

- `actions = ["sqs:SendMessage"]` and `resources` = the queue ARN.
- A `principals` block with `type = "Service"` and
  `identifiers = ["sns.amazonaws.com"]`.
- A `condition` block with `test = "ArnEquals"`,
  `variable = "aws:SourceArn"`, and `values` = the topic ARN.

Then set `policy = data.aws_iam_policy_document.<name>.json` in
`aws_sqs_queue_policy`. Each queue needs its own policy, because `resources`
is different. You can use two data sources, or one data source with
`for_each`.

</details>

<details>
<summary>tofu apply waits about 25 seconds for each queue</summary>

This is normal in this lab. Each `aws_sqs_queue` and each
`aws_sqs_queue_policy` takes about 25 seconds. For a queue, the debug log
(`TF_LOG=debug`) shows that the provider reads the queue attributes every 5
seconds during that time. OpenTofu creates resources that do not depend on
each other at the same time.

</details>

<details>
<summary>The app fails with KeyError: 'Message'</summary>

The shipping subscription uses raw message delivery. Then the body is the
order itself, without an envelope. Remove `raw_message_delivery` from the
shipping subscription and apply again. Only billing uses raw delivery.

</details>

<details>
<summary>The app shows only 1 billing receive, and the DLQ is empty</summary>

The visibility timeout of `ex02-billing` is not 5 seconds. The default is 30
seconds. The message stays hidden for longer than the 10-second wait, so the
second receive returns no message. Set `visibility_timeout_seconds = 5` and
apply again.

</details>

<details>
<summary>check.sh: "ex02-billing-dlq holds at least 1 message" fails after 2 billing receives</summary>

In this lab, SQS moves the message to the DLQ during the next receive. It does
not move the message when the visibility timeout ends. A message that is not
received again stays in `ex02-billing`. Make sure that the loop continues until
a receive returns no message.

</details>

<details>
<summary>check.sh: "The DLQ message is the raw order JSON" fails</summary>

An earlier run put an SNS envelope in the DLQ. This occurs when billing does
not use raw message delivery. Set `raw_message_delivery = true` on the billing
subscription and apply again. Then delete the old DLQ messages and run the app
again:

```bash
aws sqs purge-queue --queue-url "$(tofu output -raw billing_dlq_url)"
uv run --with boto3 python app.py
```

> **Note:** On Floci, you can purge a queue again immediately. On real AWS,
> you can purge a queue only one time in 60 seconds.

</details>

<details>
<summary>The app fails with QueueDoesNotExist</summary>

Apply Part B first. The app uses the queues that OpenTofu creates.

</details>

---

## Solution

Try the exercise first. The solution is in [`solution/`](solution/).

To run the solution, destroy your own resources first. Both use the same topic
and queue names.

> **Note:** On Floci, you can create a queue again immediately after you
> delete it. On real AWS, you must wait 60 seconds before you create a queue
> with the same name.

```bash
cd solution
tofu init -plugin-dir=../../../.terraform/providers
tofu apply
uv run --with boto3 python app.py
../check.sh
tofu destroy
```
