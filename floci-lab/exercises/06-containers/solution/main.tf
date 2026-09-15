# Exercise 06 — Containers. Solution.
#
# Flow: docker build pushes app/ to ECR. An ECS service runs one task from that
# image. The task publishes container port 80 on host port 8060.

locals {
  name      = "ex06-web"
  host_port = 8060
}

# --- ECR ---------------------------------------------------------------------

resource "aws_ecr_repository" "web" {
  name                 = local.name
  image_tag_mutability = "MUTABLE"

  # Lets `tofu destroy` delete the repository while it still holds images.
  # OpenTofu does not manage the images that docker build pushes. Use this in
  # labs only: on a real account it deletes images without a second question.
  force_delete = true
}

# --- ECS cluster -------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "ex06-cluster"
}

# --- IAM ---------------------------------------------------------------------

# The trust policy. It lets ECS tasks assume the role.
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# The execution role. The ECS agent uses it to pull the image from ECR and to
# send the container logs to CloudWatch Logs. Your code does not use it.
resource "aws_iam_role" "execution" {
  name               = "${local.name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- CloudWatch Logs ---------------------------------------------------------

# Create the log group before the task definition. OpenTofu then controls the
# retention, and `tofu destroy` deletes the log group.
resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
}

# --- Task definition ---------------------------------------------------------

resource "aws_ecs_task_definition" "web" {
  family                   = local.name
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = "${aws_ecr_repository.web.repository_url}:v1"
      essential = true
      cpu       = 128
      memory    = 64

      # bridge mode: Docker publishes containerPort on hostPort of the host.
      portMappings = [
        {
          containerPort = 80
          hostPort      = local.host_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.web.name
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# --- Service -----------------------------------------------------------------

resource "aws_ecs_service" "web" {
  name            = local.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "EC2"

  depends_on = [aws_iam_role_policy_attachment.execution]
}

# --- Outputs -----------------------------------------------------------------

output "repository_url" {
  value = aws_ecr_repository.web.repository_url
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.web.name
}

# bridge mode publishes the port on the Docker host. Colima forwards it to localhost.
output "service_url" {
  value = "http://localhost:${local.host_port}"
}
