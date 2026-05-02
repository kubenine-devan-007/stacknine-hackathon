# Public ALB — only component that accepts HTTP from the internet (task §4).
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "HTTP from internet to ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from users"
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

# All Fargate tasks (main-backend, extractor, parser) — private; only ALB and internal calls.
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name_prefix}-ecs-tasks-sg"
  description = "ECS tasks: main-backend from ALB; cross-service on app ports"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "main-backend from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "extractor from peers (main-backend)"
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "parser from peers (main-backend)"
    from_port   = 8002
    to_port     = 8002
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "PostgreSQL only from ECS tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Postgres from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "lambda" {
  name        = "${var.name_prefix}-lambda-sg"
  description = "Lambda in VPC - outbound only"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
