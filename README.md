# StackNine Invoice Processor

Upload a PDF invoice → see the extracted data on screen.

**Live app:** http://hackthon-k9-intern-devan-alb-518719741.us-east-1.elb.amazonaws.com

---

## What it does

1. You upload an invoice PDF.
2. It gets stored in S3.
3. A background pipeline pulls the text out and parses the fields.
4. You see invoice number, vendor, date, total, and line items.

That's it.

---

## What runs it

Three small Python services, all on AWS Fargate:

| Service | Job |
|---|---|
| **main-backend** | The website. Handles uploads, shows results. |
| **extractor** | Reads the raw text out of the PDF. |
| **parser** | Pulls out the invoice fields from that text. |

They share one PostgreSQL database (RDS).

---

## How a request flows

```
You upload a PDF
        │
        ▼
   main-backend  ──►  saves PDF to S3, creates a job in the DB
        │
        ▼
       S3  ──►  fires an event
        │
        ▼
     Lambda  ──►  tells main-backend "process job X"
        │
        ▼
   main-backend  ──►  asks extractor to read the PDF
                ──►  asks parser to find the fields
        │
        ▼
   Results page shows the data
```

---

## Where everything lives on AWS

- **VPC** with public + private subnets across 2 zones
- **ALB** (public) — the only thing on the internet
- **ECS Fargate** — runs the 3 services in private subnets
- **RDS PostgreSQL 15** — private, encrypted
- **S3 bucket** — private, encrypted, versioned
- **Lambda** — runs when a PDF lands in S3
- **SSM Parameter Store** — keeps the DB password and config safely
- **CloudWatch** — logs + 6 alarms + autoscaling

All Terraform. One `terraform apply` creates the whole thing.

---

## How to deploy it (5 steps)

```powershell
# 1. Sign in to AWS
aws sso login --profile Devan

# 2. Create all the AWS resources
cd infra
terraform init
terraform apply

# 3. Build and push the Docker images
cd ..
.\infra\scripts\build-push.ps1

# 4. Create the database tables (one-time)
#    Use the command printed by:
terraform output db_init_run_command

# 5. Open the app
terraform output alb_dns_name
```

Upload a PDF from `sample-invoices/` and watch it work.

To shut it all down: `terraform destroy`.

---

## Auto-deploy with GitHub Actions

Pushing to `main` automatically rebuilds and redeploys the three services. No AWS keys stored — uses GitHub OIDC.

**Setup once:**
1. `terraform output github_actions_role_arn` → copy the value
2. GitHub → Repo → Settings → Secrets → add `AWS_ROLE_ARN` with that value
3. Push to `main`

Workflow file: `.github/workflows/deploy.yml`

---

## Run it on your laptop

```bash
docker compose up --build
```

| Open | URL |
|---|---|
| Web UI | http://localhost:8000 |
| Extractor | http://localhost:8001 |
| Parser | http://localhost:8002 |

---

## Folder layout

```
.
├── main-backend/      # Web UI + orchestrator
├── extractor/         # PDF text extraction
├── parser/            # Field parsing
├── lambda/            # S3 event handler
├── db/init.sql        # Database schema
├── infra/             # All Terraform code
├── .github/workflows/ # CI/CD
├── sample-invoices/   # Test PDFs
├── README.md          # ← this file
└── WALKTHROUGH.md     # Full design + every "why"
```

---

## Want the full design story?

Open **[WALKTHROUGH.md](WALKTHROUGH.md)** — it explains every choice and trade-off (network, IAM, alarms, CI/CD, etc.) in one place.
