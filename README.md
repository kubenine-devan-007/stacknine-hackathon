# StackNine Invoice Processor — AWS Deployment

Hackathon submission for **TASK-1**: deploying the StackNine invoice processor on AWS in a secure, observable, and extensible way using Terraform.

**Live URL:** http://hackthon-k9-intern-devan-alb-518719741.us-east-1.elb.amazonaws.com
**AWS account:** `138720667646` (region `us-east-1`)
**Naming prefix:** `hackthon-k9-intern-devan-*`

---

## What the application does

A user logs in with any email, uploads an invoice PDF, and the extracted fields (invoice number, vendor, date, total, line items) appear on the results page within a few seconds. Three Python/FastAPI microservices share a PostgreSQL database:

| Service | Port | Role |
|---|---|---|
| `main-backend` | 8000 | Web UI, uploads, orchestration |
| `extractor` | 8001 | Extracts raw text from PDF (pdfplumber) |
| `parser` | 8002 | Parses fields from raw text (regex) |

---

## Architecture on AWS

```
                 Internet
                    │
                    ▼
        ┌─────────────────────┐
        │   Public ALB :80    │   internet-facing, public subnets
        └──────────┬──────────┘
                   │ /health, /
                   ▼
   ┌──────────────────────────────────────────────────────┐
   │                  Private subnets                      │
   │                                                       │
   │   ┌──────────────┐   Cloud Map (stacknine.local)      │
   │   │ main-backend │───────┬──────────┐                 │
   │   │  (Fargate)   │       │          │                 │
   │   └──────┬───────┘       ▼          ▼                 │
   │          │         ┌──────────┐ ┌────────┐            │
   │          │         │extractor │ │ parser │            │
   │          │         │(Fargate) │ │(Fargate)│           │
   │          │         └────┬─────┘ └────┬───┘            │
   │          │              │            │                 │
   │          ▼              ▼            ▼                 │
   │   ┌──────────────────────────────────────┐             │
   │   │    RDS PostgreSQL 15  (private)      │             │
   │   └──────────────────────────────────────┘             │
   │                                                       │
   │   ┌──────────────┐                                    │
   │   │   Lambda     │ ── reads /stacknine/main-backend-url
   │   │ (in VPC)     │ ── POSTs /process/{job_id}         │
   │   └──────▲───────┘                                    │
   └──────────│────────────────────────────────────────────┘
              │ S3 ObjectCreated event
   ┌──────────┴───────┐
   │  S3 uploads      │  AES256, private, versioned, HTTPS-only
   └──────────────────┘
```

### End-to-end flow

1. Browser uploads a PDF to `main-backend` through the ALB.
2. `main-backend` writes the PDF to S3 at `{job_id}/{filename}.pdf` and creates a job row in RDS.
3. S3 emits `ObjectCreated` → Lambda reads `job_id` from the key, looks up `/stacknine/main-backend-url` in SSM, and calls `POST /process/{job_id}`.
4. `main-backend` calls `extractor.stacknine.local` (Cloud Map) → extractor downloads the PDF from S3, extracts text, writes to RDS.
5. `main-backend` calls `parser.stacknine.local` → parser reads text from RDS, parses fields, marks the job `done`.
6. The results page (auto-refreshing every 3 s) shows the extracted invoice.

---

## What Terraform provisions

All under `infra/`. Each `.tf` file owns one logical area:

| File | Resources |
|---|---|
| `vpc.tf` | VPC `10.0.0.0/16` across 2 AZs, 2 public + 2 private subnets, single NAT |
| `security_groups.tf` | ALB, ECS-tasks, RDS, Lambda — least-privilege ingress chains |
| `rds.tf` | PostgreSQL 15 `db.t3.micro`, encrypted, private subnets, random password |
| `ssm.tf` | `/stacknine/db-host`, `db-name`, `db-user`, `db-password` (SecureString), `main-backend-url` |
| `ecr.tf` | Three repositories (AES256, scan-on-push, lifecycle keeps last 5) |
| `alb.tf` | Public ALB → `main-backend` target group with `/health` checks |
| `service_discovery.tf` | Cloud Map private DNS namespace `stacknine.local` |
| `iam.tf` | One execution role + three task roles + Lambda role, all least-privilege |
| `ecs.tf` | Fargate cluster + 3 services, log groups, task definitions reading from SSM |
| `s3.tf` | Uploads bucket, public-access blocked, versioned, bucket policy enforces HTTPS |
| `lambda.tf` | S3-trigger function in VPC, retries=2, log group, S3 notification |
| `observability.tf` | App Auto Scaling on `main-backend` + 6 CloudWatch alarms |
| `db_init.tf` | One-shot Fargate task that runs `db/init.sql` against private RDS |
| `cicd.tf` | GitHub OIDC provider + a deploy role scoped to this repo |

Total: ~80 AWS resources, one `terraform apply` end to end.

---

## Why these choices

**Private RDS, no bastion.** The DB is in private subnets and the only ingress is from the ECS-tasks security group on TCP 5432. No public IP, no jump box. Schema is applied by a one-shot Fargate task (`db_init.tf`) that runs in the VPC — the only thing that ever reaches the DB is a workload inside the VPC.

**Cloud Map instead of internal ALBs.** `extractor` and `parser` are not internet-facing. Adding internal ALBs for them would have meant two more load balancers, two more target groups, two more sets of listeners. Cloud Map gives them stable DNS names (`extractor.stacknine.local`, `parser.stacknine.local`) for the cost of one Route 53 hosted zone. Same outcome, much less infrastructure.

**S3 → Lambda → main-backend.** The upload HTTP request returns the moment the PDF lands in S3 — the user doesn't wait for extraction. Lambda is the cheapest, lowest-friction way to bridge an S3 event into a backend API call: zero servers when idle, runs for ~hundreds of milliseconds per invoice.

**SSM for everything configurable.** No secrets in task definitions, no plaintext env vars. The DB password is `SecureString` (KMS-encrypted with `aws/ssm`). The ECS execution role is allowed `kms:Decrypt` only against that key, and `ssm:GetParameters` only on `/stacknine/*`. To rotate a value, you change the parameter and bounce the service — no redeploy.

**Per-task IAM roles.** `main-backend` can `s3:PutObject` on the uploads bucket; `extractor` can `s3:GetObject`; `parser` has no S3 access at all. The execution role (which pulls images and writes logs) is separate from the task roles (which the application code uses). One role per concern.

**Auto-scaling only where it matters.** `main-backend` scales 1→4 tasks at 60% CPU because it terminates user HTTP requests and is the obvious hotspot under load. `extractor` and `parser` are pinned at one task each — keeping the autoscaling story simple, while still meeting the requirement.

**Single NAT, not one per AZ.** Two NATs would be more available but cost twice as much for a hackathon. The trade-off is documented; production would use one per AZ.

**GitHub Actions OIDC for CI/CD.** No long-lived AWS keys in GitHub. Federation is scoped to exactly one repo, and the deploy role can only push to these three ECR repos and force-deploy these three ECS services.

---

## Security guardrails (applied)

- S3 bucket: public access blocked, AES256 at rest, HTTPS-only via bucket policy, versioned.
- RDS: storage encrypted, private subnets, random 32-char password, not publicly accessible.
- SSM: `db-password` is `SecureString` (KMS), readable only by the ECS execution role.
- Network: ALB is the only public ingress (HTTP:80). Tasks accept only ALB → 8000 and intra-SG 8001/8002. RDS accepts only from tasks. Lambda is egress-only.
- IAM: each role has the smallest action+resource set its job actually needs.

---

## Observability

- All CloudWatch log groups have a 14-day retention.
- Auto-scaling target tracking on `main-backend` CPU at 60%, range 1–4.
- Six alarms, evaluated every minute:
  - `main-backend-running-zero` — service has zero healthy tasks
  - `main-backend-cpu-high` — CPU > 80% for 2 minutes
  - `main-backend-mem-high` — memory > 80% for 2 minutes
  - `tg-unhealthy-hosts` — any unhealthy target
  - `alb-target-5xx` — > 5 target 5xx in 5 minutes
  - `lambda-errors` — any Lambda invocation error

---

## Deployment

Prereqs on the operator machine: AWS CLI v2 with SSO profile `Devan`, Terraform ≥ 1.5, Docker.

```powershell
# 1. Sign in to AWS
aws sso login --profile Devan

# 2. Provision all infrastructure
cd infra
terraform init
terraform apply

# 3. Build and push the three service images to ECR
cd ..
.\infra\scripts\build-push.ps1

# 4. Apply the database schema (runs inside the VPC)
#    Use the command printed by `terraform output db_init_run_command`
aws ecs run-task --cluster ... --task-definition ... --network-configuration ...

# 5. Force ECS to pull the freshly pushed :latest images
aws ecs update-service --cluster hackthon-k9-intern-devan-cluster `
  --service hackthon-k9-intern-devan-main-backend-svc --force-new-deployment `
  --profile Devan --region us-east-1
# repeat for extractor-svc and parser-svc
```

Open `terraform output alb_dns_name` and upload a sample PDF from `sample-invoices/`.

Tear down with `terraform destroy` to stop NAT charges.

---

## CI/CD

`cicd.tf` provisions a GitHub OIDC provider and a deploy role. The workflow at `.github/workflows/deploy.yml` triggers on every push to `main` and on `workflow_dispatch`:

1. Authenticate to AWS using OIDC (no long-lived keys).
2. Build the three images in parallel (matrix strategy), tagged `:latest` and `:<sha>`.
3. Push to ECR.
4. `aws ecs update-service --force-new-deployment` for all three services.

One-time setup after `terraform apply`:

```powershell
terraform output github_actions_role_arn
```

Add the ARN as a GitHub repository secret named `AWS_ROLE_ARN` (Settings → Secrets and variables → Actions). Push to `main` and the pipeline runs automatically.

---

## Repository layout

```
hackathon-intern/
├── .github/workflows/
│   └── deploy.yml            # CI/CD pipeline
├── db/
│   └── init.sql              # Schema (4 tables)
├── main-backend/             # FastAPI: UI, uploads, orchestration
├── extractor/                # FastAPI: pdfplumber text extraction
├── parser/                   # FastAPI: regex field parsing
├── lambda/
│   └── handler.py            # S3 event → POST /process/{job_id}
├── infra/                    # All Terraform
│   ├── *.tf
│   ├── scripts/build-push.ps1
│   └── README.md             # Operational notes
├── sample-invoices/          # 6 PDFs to test with
├── docker-compose.yml        # Local dev stack
└── README.md                 # This file
```

---

## SSM parameters

| Parameter | Type | Purpose |
|---|---|---|
| `/stacknine/db-host` | String | RDS endpoint |
| `/stacknine/db-name` | String | Database name (`stacknine`) |
| `/stacknine/db-user` | String | DB user (`postgres`) |
| `/stacknine/db-password` | SecureString | DB password (random, KMS-encrypted) |
| `/stacknine/main-backend-url` | String | ALB URL — used by Lambda |

All five are read at container startup; nothing sensitive is baked into task definitions.

---

## Local development

```bash
docker compose up --build
```

| Service | URL |
|---|---|
| Web UI | http://localhost:8000 |
| Extractor | http://localhost:8001 |
| Parser | http://localhost:8002 |
| PostgreSQL | localhost:5433 |
