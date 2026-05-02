# One-shot Fargate task that applies db/init.sql to RDS from inside the VPC.
# Required because RDS is private (TASK-1 §5: not internet-reachable).
# The SQL is embedded at apply time so the task is self-contained.

locals {
  init_sql = file("${path.module}/../db/init.sql")
}

resource "aws_cloudwatch_log_group" "db_init" {
  name              = "/ecs/${var.name_prefix}-db-init"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "db_init" {
  family                   = "${var.name_prefix}-db-init"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.task_parser.arn

  container_definitions = jsonencode([
    {
      name       = "db-init"
      image      = "postgres:15-alpine"
      essential  = true
      entryPoint = ["sh", "-c"]
      command = [
        "psql -v ON_ERROR_STOP=1 -h $DB_HOST -U $DB_USER -d $DB_NAME <<'SQL'\n${local.init_sql}\nSQL"
      ]
      environment = [
        { name = "PGPASSWORD_VARNAME", value = "DB_PASSWORD" }
      ]
      secrets = [
        { name = "DB_HOST", valueFrom = aws_ssm_parameter.db_host.arn },
        { name = "DB_NAME", valueFrom = aws_ssm_parameter.db_name.arn },
        { name = "DB_USER", valueFrom = aws_ssm_parameter.db_user.arn },
        { name = "PGPASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.db_init.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "init"
        }
      }
    }
  ])
}

output "db_init_run_command" {
  description = "One-shot Fargate task to apply db/init.sql from inside the VPC."
  value       = "aws ecs run-task --cluster ${aws_ecs_cluster.main.name} --launch-type FARGATE --task-definition ${aws_ecs_task_definition.db_init.family} --network-configuration \"awsvpcConfiguration={subnets=[${join(",", module.vpc.private_subnets)}],securityGroups=[${aws_security_group.ecs_tasks.id}],assignPublicIp=DISABLED}\" --profile Devan --region ${data.aws_region.current.name}"
}
