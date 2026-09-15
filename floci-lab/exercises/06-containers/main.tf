# Exercise 06 — Containers. Part B.
#
# Complete each TODO, then run `tofu plan` and `tofu apply`.
# Resource documentation: https://search.opentofu.org/provider/hashicorp/aws/latest
#
# Flow: docker build pushes app/ to ECR. An ECS service runs one task from that
# image. The task publishes container port 80 on host port 8060.

# --- Step 1: complete TODO 1 and TODO 2, then apply. Then push the image. ------

# TODO 1: Create an ECR repository named "ex06-web" with mutable image tags.
#         Resource: aws_ecr_repository

# TODO 2: Output the repository URL as "repository_url".

# --- Step 2: complete TODO 3 to TODO 8, then apply. ---------------------------

# TODO 3: Create an ECS cluster named "ex06-cluster".
#         Resource: aws_ecs_cluster

# TODO 4: Create the task execution role "ex06-web-execution-role".
#         The trust policy allows "sts:AssumeRole" for the service "ecs-tasks.amazonaws.com".
#         Attach the AWS managed policy:
#         arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
#         Data source: aws_iam_policy_document.
#         Resources: aws_iam_role, aws_iam_role_policy_attachment

# TODO 5: Create the log group "/ecs/ex06-web". Keep the logs for 7 days.
#         Resource: aws_cloudwatch_log_group

# TODO 6: Create the task definition with the family "ex06-web".
#         Use network_mode "bridge", requires_compatibilities ["EC2"], and the execution role ARN.
#         Write container_definitions with jsonencode(). Use one container:
#         - name "web", essential true, cpu 128, memory 64
#         - image "<repository URL>:v1". Use the repository_url attribute, not a typed string.
#         - portMappings: containerPort 80, hostPort 8060, protocol "tcp"
#         - logConfiguration: logDriver "awslogs" with the options
#           awslogs-group (the log group name attribute), awslogs-region "us-east-1",
#           and awslogs-stream-prefix "ecs"
#         Resource: aws_ecs_task_definition

# TODO 7: Create the service "ex06-web" in the cluster.
#         Use the task definition ARN, desired_count 1, and launch_type "EC2".
#         Do not set wait_for_steady_state. Read the Hints section of the README to learn why.
#         Resource: aws_ecs_service

# TODO 8: Add these outputs:
#         "cluster_name" = the cluster name
#         "service_name" = the service name
#         "service_url"  = "http://localhost:8060"
