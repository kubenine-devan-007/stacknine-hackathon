# StackNine hackathon — Terraform (TASK-1)

## What this creates

Matches **TASK-1.md**: VPC (already applied), RDS PostgreSQL 15, SSM (`/stacknine/*`), three ECR repos, public ALB → `main-backend`, Cloud Map (`extractor.stacknine.local`, `parser.stacknine.local`), three Fargate services, S3 + Lambda trigger, IAM least-privilege, logs + retention, CPU autoscaling on `main-backend`, CloudWatch alarms.

## Before `terraform apply`

1. **AWS SSO:** `aws sso login --profile Devan`
2. **Account / region:** profile `Devan` → account `138720667646`, region **`us-east-1`** (see `variables.tf`).

## Apply

```powershell
cd infra
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

If **RDS** fails on `engine_version`, edit `rds.tf` to a version returned by:

```powershell
aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[?starts_with(EngineVersion, '15.')].EngineVersion" --output text --profile Devan --region us-east-1
```

## Docker images (required before services stay healthy)

ECR repos are empty until you build and push:

```powershell
cd ..
pwsh infra/scripts/build-push.ps1
```

Then force ECS to pick up new images:

```powershell
aws ecs update-service --cluster hackthon-k9-intern-devan-cluster --service hackthon-k9-intern-devan-main-backend-svc --force-new-deployment --profile Devan --region us-east-1
# repeat for extractor + parser services
```

Or run `terraform apply` again after pushing (task definitions already point at `:latest`).

## Database schema (manual — TASK-1)

After RDS is **available**, from a machine that can reach it (SSM port forward, VPN, or temporarily allow your IP — **not** in this minimal stack):

```powershell
$env:PGPASSWORD = "<from SSM /stacknine/db-password or terraform state>"
psql -h <rds_address_from_output> -U postgres -d stacknine -f db/init.sql
```

Or Docker:

```powershell
docker run --rm -e PGPASSWORD=... -v ${PWD}/db/init.sql:/init.sql postgres:15 `
  psql -h <rds_address> -U postgres -d stacknine -f /init.sql
```

## Smoke test

1. Open **`terraform output alb_dns_name`**
2. Login with any email / password
3. Upload a PDF from `sample-invoices/`
4. Wait for extracted fields on the results page

## Destroy (stop NAT charges)

```powershell
terraform destroy
```
