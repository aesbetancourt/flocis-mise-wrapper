"""Exercise 06 — Containers. Part C.

Complete each TODO. Run inside the lab folder:
    uv run --with boto3 python app.py

boto3 needs no endpoint or keys. Inside the lab, boto3 reads the floci profile.
boto3 ECS reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ecs.html
"""

import re
import time
import urllib.request

import boto3

CLUSTER = "ex06-cluster"
SERVICE = "ex06-web"
SERVICE_URL = "http://localhost:8060/"

ecs = boto3.client("ecs")


def task_arns(desired_status):
    """Return the ARNs of the service tasks with this desired status."""
    paginator = ecs.get_paginator("list_tasks")
    arns = []
    for page in paginator.paginate(
        cluster=CLUSTER, serviceName=SERVICE, desiredStatus=desired_status
    ):
        arns.extend(page["taskArns"])
    return arns


def describe(arns):
    """Return the task descriptions. describe_tasks accepts 100 ARNs in one call."""
    tasks = []
    for start in range(0, len(arns), 100):
        tasks.extend(
            ecs.describe_tasks(cluster=CLUSTER, tasks=arns[start : start + 100])[
                "tasks"
            ]
        )
    return tasks


# TODO 1: Wait until the service runs its desired number of tasks.
#         Then print desiredCount and runningCount of the service.
#         Methods: ecs.get_waiter("services_stable").wait(...), describe_services

# TODO 2: Print the running tasks. For each task, print the task ID, lastStatus, and image.
#         The task ID is the last part of the task ARN.
#         Example: tasks = describe(task_arns("RUNNING"))

# TODO 3: Send a GET request to SERVICE_URL. Print the status code and the text in <h1>.
#         Method: urllib.request.urlopen. Example: re.search(r"<h1>(.*?)</h1>", page)

# TODO 4: Scale the service to 2 tasks. Then find out why the second task cannot start.
#         a. Keep the set of STOPPED task ARNs before you scale.
#         b. Call update_service with desiredCount=2.
#         c. Every 2 seconds, for up to 60 seconds, look for a new STOPPED task.
#         d. Print the stoppedReason of the new task. Use time.sleep.

# TODO 5: Scale the service back to 1 task. Wait until it is stable, then print the running tasks.
