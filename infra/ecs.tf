# ---------------------------------------------------------------------------
# Log groups — retention so logs are not kept forever (task §9).
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "main_backend" {
  name              = "/ecs/${var.name_prefix}-main-backend"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "extractor" {
  name              = "/ecs/${var.name_prefix}-extractor"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/ecs/${var.name_prefix}-parser"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"
}

# ---------------------------------------------------------------------------
# main-backend
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "main_backend" {
  family                   = "${var.name_prefix}-main-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.task_main_backend.arn

  container_definitions = jsonencode([
    {
      name      = "main-backend"
      image     = local.image_main
      essential = true
      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "DB_PORT", value = "5432" },
        { name = "EXTRACTOR_URL", value = "http://extractor.stacknine.local:8001" },
        { name = "PARSER_URL", value = "http://parser.stacknine.local:8002" },
        { name = "S3_BUCKET", value = aws_s3_bucket.uploads.bucket },
        { name = "ENV", value = "production" }
      ]
      secrets = [
        { name = "DB_HOST", valueFrom = aws_ssm_parameter.db_host.arn },
        { name = "DB_NAME", valueFrom = aws_ssm_parameter.db_name.arn },
        { name = "DB_USER", valueFrom = aws_ssm_parameter.db_user.arn },
        { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main_backend.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "main"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "main_backend" {
  name            = "${var.name_prefix}-main-backend-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main_backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_backend.arn
    container_name   = "main-backend"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]
}

# ---------------------------------------------------------------------------
# extractor
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "extractor" {
  family                   = "${var.name_prefix}-extractor"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.task_extractor.arn

  container_definitions = jsonencode([
    {
      name      = "extractor"
      image     = local.image_ext
      essential = true
      portMappings = [
        {
          containerPort = 8001
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "DB_PORT", value = "5432" }
      ]
      secrets = [
        { name = "DB_HOST", valueFrom = aws_ssm_parameter.db_host.arn },
        { name = "DB_NAME", valueFrom = aws_ssm_parameter.db_name.arn },
        { name = "DB_USER", valueFrom = aws_ssm_parameter.db_user.arn },
        { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.extractor.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ext"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "extractor" {
  name            = "${var.name_prefix}-extractor-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.extractor.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.extractor.arn
  }
}

# ---------------------------------------------------------------------------
# parser
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "parser" {
  family                   = "${var.name_prefix}-parser"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.task_parser.arn

  container_definitions = jsonencode([
    {
      name      = "parser"
      image     = local.image_parse
      essential = true
      portMappings = [
        {
          containerPort = 8002
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "DB_PORT", value = "5432" }
      ]
      secrets = [
        { name = "DB_HOST", valueFrom = aws_ssm_parameter.db_host.arn },
        { name = "DB_NAME", valueFrom = aws_ssm_parameter.db_name.arn },
        { name = "DB_USER", valueFrom = aws_ssm_parameter.db_user.arn },
        { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.parser.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "parse"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "parser" {
  name            = "${var.name_prefix}-parser-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.parser.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.parser.arn
  }
}
