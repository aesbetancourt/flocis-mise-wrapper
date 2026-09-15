"""Exercise 06 — Containers. Solution for Part C.

Run inside the lab folder:
    uv run --with boto3 python app.py
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


def print_running_tasks():
    tasks = describe(task_arns("RUNNING"))
    print(f"{len(tasks)} running task(s):")
    for task in tasks:
        task_id = task["taskArn"].split("/")[-1]
        revision = task["taskDefinitionArn"].split(":")[-1]
        image = task["containers"][0]["image"]
        print(f"  {task_id}  {task['lastStatus']}  revision {revision}  {image}")


def wait_until_stable():
    ecs.get_waiter("services_stable").wait(
        cluster=CLUSTER,
        services=[SERVICE],
        WaiterConfig={"Delay": 5, "MaxAttempts": 24},
    )
    service = ecs.describe_services(cluster=CLUSTER, services=[SERVICE])["services"][0]
    print(
        f"Service {SERVICE} is stable: "
        f"desired={service['desiredCount']} running={service['runningCount']}"
    )


# 1. Wait until the service runs its desired number of tasks.
wait_until_stable()

# 2. Print the running tasks.
print_running_tasks()

# 3. Send an HTTP request to the container through the host port.
with urllib.request.urlopen(SERVICE_URL, timeout=10) as response:
    page = response.read().decode()
    heading = re.search(r"<h1>(.*?)</h1>", page)
    print(
        f"GET {SERVICE_URL} -> {response.status}, h1={heading.group(1) if heading else None!r}"
    )

# 4. Scale to 2 tasks. The second task needs the same host port, so it cannot start.
stopped_before = set(task_arns("STOPPED"))
ecs.update_service(cluster=CLUSTER, service=SERVICE, desiredCount=2)
print("Scaled to desiredCount=2. Waiting for a start failure...")

new_stopped = []
deadline = time.time() + 60
while not new_stopped and time.time() < deadline:
    time.sleep(2)
    new_stopped = [arn for arn in task_arns("STOPPED") if arn not in stopped_before]

if new_stopped:
    reason = describe(new_stopped[:1])[0].get("stoppedReason", "")
    # Docker returns a long message. Keep only the part about the port.
    match = re.search(r"Bind for [^\"]*", reason)
    print(f"A new task stopped: {match.group(0) if match else reason[:120]}")
else:
    print("No new task stopped in 60 seconds.")

service = ecs.describe_services(cluster=CLUSTER, services=[SERVICE])["services"][0]
print(f"desired={service['desiredCount']} running={service['runningCount']}")

# 5. Scale back to 1 task.
ecs.update_service(cluster=CLUSTER, service=SERVICE, desiredCount=1)
print("Scaled back to desiredCount=1.")
wait_until_stable()
print_running_tasks()
