"""Exercise 02 — Messaging. Part C.

Complete each TODO. Run inside the lab folder:
    uv run --with boto3 python app.py

The clients need no endpoint or keys. Inside the lab, boto3 reads the floci profile.
boto3 SNS reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/sns.html
boto3 SQS reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/sqs.html
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

# TODO 1: Publish ORDER to the topic as a JSON string. Print the message ID.
#         Method: sns.publish

# TODO 2: Receive one message from shipping_url. Use WaitTimeSeconds=5.
#         The body is an SNS envelope. Read the order from its "Message" field.
#         Print the order ID. Then delete the message.
#         Methods: sqs.receive_message, sqs.delete_message

# TODO 3: The billing payment fails every time. Do not delete the message.
#         Receive from billing_url in a loop. Use WaitTimeSeconds=10.
#         Print the ApproximateReceiveCount of each message.
#         Stop the loop when a receive returns no message.
#         Method: sqs.receive_message with MessageSystemAttributeNames=["ApproximateReceiveCount"]

# TODO 4: Receive the messages from dlq_url and print each body.
#         Use VisibilityTimeout=0. The messages then stay visible for check.sh.
#         Method: sqs.receive_message
