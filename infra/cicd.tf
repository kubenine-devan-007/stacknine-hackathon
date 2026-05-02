# GitHub Actions OIDC trust + a least-privilege deploy role.
# Lets the workflow `.github/workflows/deploy.yml` push images to ECR
# and force a new deployment on the three ECS services. No long-lived AWS keys.

variable "github_repo" {
  description = "GitHub <owner>/<repo> allowed to assume the deploy role."
  type        = string
  default     = "kubenine-devan-007/stacknine-hackathon"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions" {
  name = "${var.name_prefix}-gha-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "gha_ecr" {
  name = "${var.name_prefix}-gha-ecr"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage"
        ]
        Resource = [for r in aws_ecr_repository.service : r.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy" "gha_ecs" {
  name = "${var.name_prefix}-gha-ecs"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ForceNewDeployment"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = [
          aws_ecs_service.main_backend.id,
          aws_ecs_service.extractor.id,
          aws_ecs_service.parser.id
        ]
      }
    ]
  })
}

output "github_actions_role_arn" {
  description = "Paste this into GitHub Actions secret AWS_ROLE_ARN."
  value       = aws_iam_role.github_actions.arn
}
