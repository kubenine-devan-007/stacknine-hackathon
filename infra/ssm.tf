# Required paths from TASK-1 §8 / README — app + Lambda read these names.
# Values injected into ECS as secrets; Lambda reads main-backend-url.

resource "aws_ssm_parameter" "db_host" {
  name  = "/stacknine/db-host"
  type  = "String"
  value = aws_db_instance.main.address
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/stacknine/db-name"
  type  = "String"
  value = "stacknine"
}

resource "aws_ssm_parameter" "db_user" {
  name  = "/stacknine/db-user"
  type  = "String"
  value = "postgres"
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/stacknine/db-password"
  type  = "SecureString"
  value = random_password.db_master.result
}

resource "aws_ssm_parameter" "main_backend_url" {
  name  = "/stacknine/main-backend-url"
  type  = "String"
  value = "http://${aws_lb.main.dns_name}"

  depends_on = [aws_lb.main]
}
