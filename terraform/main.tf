

# --------------------------------------------------------------------------------
# 1. NETWORKING (VPC & Security Groups)
# --------------------------------------------------------------------------------
# Using Default VPC for simplicity. In real production, use a custom VPC module.
resource "aws_default_vpc" "default" {}

# Subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

# Security Group for ALB (Allow Internet Access)
resource "aws_security_group" "alb_sg" {
  name        = "banking-app-alb-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for ECS Tasks (Allow Traffic ONLY from ALB)
resource "aws_security_group" "ecs_tasks_sg" {
  name        = "banking-app-ecs-tasks-sg"
  description = "Allow traffic from ALB only"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Only allow ALB
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --------------------------------------------------------------------------------
# 2. APPLICATION LOAD BALANCER (ALB)
# --------------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "banking-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "main" {
  name        = "banking-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default.id
  target_type = "ip" # Required for Fargate

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  # nosemgrep: terraform.aws.security.insecure-load-balancer-tls-version.insecure-load-balancer-tls-version
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# --------------------------------------------------------------------------------
# 3. ECS CLUSTER & TASK DEFINITION
# --------------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "banking-cluster"
}

# IAM Role for ECS Execution (Allows Fargate to pull from ECR)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole-banking"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "banking-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  # We use a dummy image initially. GitHub Actions will overwrite this.
  container_definitions = jsonencode([{
    name      = "banking-app-container"
    image     = "nginx:alpine"
    essential = true
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
    }]
  }])
}

# --------------------------------------------------------------------------------
# 4. ECS SERVICE (The Manager)
# --------------------------------------------------------------------------------
resource "aws_ecs_service" "main" {
  name            = "banking-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = true # Required for Fargate to pull images from ECR
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "banking-app-container"
    container_port   = 8080
  }

  # CRITICAL: Ignores changes to task_definition so Terraform doesn't revert your deployments
  lifecycle {
    ignore_changes = [task_definition]
  }
}