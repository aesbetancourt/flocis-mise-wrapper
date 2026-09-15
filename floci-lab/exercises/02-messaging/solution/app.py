"""Exercise 02 — Messaging. Solution for Part C.

Run inside the lab folder:
    uv run --with boto3 python app.py
"""

import json

import boto3

# The value of `tofu output topic_arn`.
TOPIC_ARN = "arn:aws:sns:us-east-1:000000000000:ex02-orders"
ORDER = {"order_id": "1001", "item": "book", "quantity": 1}

sns = boto3.client("sns")
sqs = boto3.client("sqs")

shipping_url = sqs.get_queue_url(QueueName="ex02-shipping")["QueueUrl"]
billing_url = sqs.get_queue_url(QueueName="ex02-billing")["QueueUrl"]
dlq_url = sqs.get_queue_url(QueueName="ex02-billing-dlq")["QueueUrl"]

# 1. Publish the order one time. SNS sends a copy to each subscribed queue.
message_id = sns.publish(TopicArn=TOPIC_ARN, Message=json.dumps(ORDER))["MessageId"]
print(f"Published order {ORDER['order_id']}. Message ID: {message_id}")

# 2. Shipping: receive the copy, read the order from the envelope, then delete it.
#    WaitTimeSeconds turns on long polling: the call waits for a message.
messages = sqs.receive_message(QueueUrl=shipping_url, WaitTimeSeconds=5).get("Messages", [])
if not messages:
    raise SystemExit("Shipping: no message. Make sure the shipping subscription exists.")
envelope = json.loads(messages[0]["Body"])
order = json.loads(envelope["Message"])
print(f"Shipping: envelope type {envelope['Type']}. Order {order['order_id']} is shipped.")
sqs.delete_message(QueueUrl=shipping_url, ReceiptHandle=messages[0]["ReceiptHandle"])

# 3. Billing: the payment fails every time, so the app never deletes the message.
#    After the visibility timeout (5 s), SQS delivers the message again. After
#    2 receives, the next receive moves it to the DLQ and returns nothing.
#    The 10-second wait is longer than the visibility timeout. Each call can
#    wait for the next delivery.
receives = 0
while True:
    messages = sqs.receive_message(
        QueueUrl=billing_url,
        WaitTimeSeconds=10,
        MessageSystemAttributeNames=["ApproximateReceiveCount"],
    ).get("Messages", [])
    if not messages:
        break
    receives += 1
    count = messages[0]["Attributes"]["ApproximateReceiveCount"]
    print(f"Billing: receive {receives}, receive count {count}. Payment failed. Message not deleted.")
print("Billing: the last receive returned no message.")

# 4. Read the DLQ. VisibilityTimeout=0 keeps the message visible for check.sh.
messages = sqs.receive_message(
    QueueUrl=dlq_url, WaitTimeSeconds=5, VisibilityTimeout=0, MaxNumberOfMessages=10
).get("Messages", [])
print(f"Dead-letter queue: {len(messages)} message(s).")
for message in messages:
    print(f"  {message['Body']}")
