# Hackathon — Task 1: Deploy StackNine Invoice Processor on AWS

**Time allowed:** 2 hours  
**Points:** 100  
**AWS Account:** You have your own dedicated account. Work independently.

---

## Background

StackNine is a US-based fintech company building an invoice processing platform. The application accepts invoice PDF uploads from users, extracts structured data from them (vendor, date, total, line items), and returns the results through a web interface.

All users are currently in the United States. The application receives around **1,000 requests per month** today. The team is small but growing — new microservices will be added over time.

You are joining as the first infrastructure engineer. Your job is to deploy this application on AWS in a way that is secure, observable, and easy to extend.

---

## Application Architecture

The application is made up of **three independent Python/FastAPI microservices** and a **PostgreSQL database**.

```
                         ┌──────────────────────────────────┐
                         │         main-backend (8000)       │
                         │  - Serves the web UI (HTML)       │
                         │  - Accepts PDF uploads            │
                         │  - Saves files to S3              │
                         │  - Orchestrates the pipeline      │
                         └──────────────┬───────────────────┘
                                        │
                         ┌──────────────┼────────────────┐
                         ▼                               ▼
              ┌──────────────────┐          ┌──────────────────┐
              │  extractor (8001) │          │  parser (8002)   │
              │  - Downloads PDF  │          │  - Reads raw     │
              │    from S3        │          │    text from DB  │
              │  - Extracts text  │          │  - Parses fields │
              │  - Saves to DB    │          │  - Saves invoice │
              └──────────────────┘          └──────────────────┘
                         │                               │
                         └───────────────┬───────────────┘
                                         ▼
                                    PostgreSQL
```

Each service has its own `Dockerfile` and `requirements.txt`. The database schema is in `db/init.sql`.

---

## Request Flow

This is what happens from the moment a user uploads an invoice PDF:

```
1. User opens the app in a browser and uploads an invoice PDF

2. main-backend receives the file upload
   └─ Saves the PDF to S3
      Key format: {job_id}/{filename}.pdf
   └─ Creates a job record in PostgreSQL (status: pending)

3. S3 fires an ObjectCreated event

4. Lambda receives the event
   └─ Reads the S3 object key → extracts job_id
   └─ Reads the main-backend URL from SSM Parameter Store
   └─ Calls POST /process/{job_id} on main-backend via the load balancer

5. main-backend orchestrates the pipeline:
   └─ Calls POST /extract on extractor
      └─ extractor downloads PDF from S3
      └─ Extracts raw text using pdfplumber
      └─ Saves raw text to PostgreSQL
   └─ Calls POST /parse on parser
      └─ parser reads raw text from PostgreSQL
      └─ Parses fields: invoice number, vendor, date, total, line items
      └─ Saves structured data to PostgreSQL
      └─ Updates job status to "done"

6. Browser polls the results page every 3 seconds
   └─ When status = done → displays extracted invoice data
```

---

## What You Must Build

### 1. Network

Design a VPC for this application. Consider:
- All users are in the US — pick your region accordingly
- The application must tolerate the failure of a single availability zone
- Not everything in this stack needs to be reachable from the internet — design your subnets to reflect that

> **Hint:** A load balancer that faces the internet and application containers that process sensitive financial documents have different exposure requirements.

---

### 2. Container Registry

All three services must be built as Docker images and pushed to **Amazon ECR** before ECS can run them. Your infrastructure code must include the ECR repositories.

Build and push workflow (your responsibility):
```bash
# Authenticate, build, tag, push — for each of the three services
```

---

### 3. Application Services on ECS

Deploy all three services (`main-backend`, `extractor`, `parser`) on **Amazon ECS with Fargate**.

**For each service, you must have:**

| Requirement | Notes |
|---|---|
| ECS Cluster | One cluster for all three services is fine |
| Task Definition | CPU, memory, image, environment, secrets |
| ECS Service | Desired count, subnet placement, security group |
| CloudWatch Log Group | Logs from every container |
| CloudWatch Alarms | See observability section below |

**Security group rules for ECS tasks:**
- Tasks should only accept inbound traffic from the load balancer — not from anywhere else
- Tasks must be able to reach the database, S3, SSM, ECR, and CloudWatch

**For ECS secrets:** All sensitive values (DB password, DB host, etc.) must be sourced from SSM Parameter Store as container secrets — not as plaintext environment variables.

---

### 4. Load Balancer (ALB)

The application is accessed through a browser. The entry point is an **Application Load Balancer**.

- The ALB must be the **only** publicly accessible component for HTTP traffic
- Security group on the ALB: restrict inbound to only what is necessary
- The ALB routes traffic to the ECS services — configure your target groups and health checks
- `main-backend` has a `/health` endpoint. So do `extractor` and `parser`.

> **Hint:** Think about how the three services communicate with each other. Does every service need to be directly exposed through the ALB? Or is there another way?

---

### 5. Database (PostgreSQL 15)

The application requires PostgreSQL 15. **Where and how you run it is your decision.**

Options include EC2, Fargate, or a managed service. There are tradeoffs to each. Whatever you choose:
- The database must **not** be reachable from the internet
- The schema in `db/init.sql` must be applied before the application handles traffic
- The database password must be stored in SSM Parameter Store as a `SecureString`

Be ready to explain your database decision during the walkthrough.

---

### 6. S3 and Lambda

The invoice upload pipeline depends on:

**S3 uploads bucket:**
- Private — no public access
- Encrypted at rest — choose your encryption approach and be ready to justify it
- Configured to send `ObjectCreated` events to Lambda

**Lambda function:**
- Source code is in `lambda/handler.py`
- Reads the main-backend URL from SSM parameter `/stacknine/main-backend-url`
- Calls `POST /process/{job_id}` on the main-backend via the ALB
- Needs appropriate IAM permissions — and only those permissions

> **Hint:** What happens if Lambda fires and the backend is not yet ready to respond? Is one attempt sufficient for a financial document processing pipeline?

---

### 7. Security and IAM

**S3:**
- Block all public access at the bucket level
- Encrypt all objects — `aws:kms` or `AES256`, justify your choice
- The bucket policy should only allow access from the services that need it

**IAM — task roles:**
Each ECS service must have its own task role. Before granting any permission, confirm the service actually needs it.

Ask yourself:
- Does `parser` need to read or write to S3?
- Does `extractor` need to write invoice records to the database?
- Does `main-backend` need to read from S3, or only write to it?
- Does Lambda need database access?

**IAM — task execution role:**
The execution role (used by ECS to pull images and inject secrets) needs access to ECR and SSM. Scope it tightly.

**General rule:** No `*` in `Resource` fields. Scope every policy to specific ARNs.

---

### 8. SSM Parameter Store

All application runtime configuration must live in SSM. The following parameters are required:

| Parameter | Type | Description |
|---|---|---|
| `/stacknine/db-host` | String | Database hostname or NLB DNS |
| `/stacknine/db-name` | String | Database name |
| `/stacknine/db-user` | String | Database user |
| `/stacknine/db-password` | SecureString | Database password (KMS encrypted) |
| `/stacknine/main-backend-url` | String | ALB DNS name — used by Lambda |

All parameter names must follow the hackathon naming convention.

---

### 9. Observability

#### Logging
Every ECS service and Lambda must send logs to CloudWatch Log Groups. Set a retention period — logs should not live forever.

#### Auto Scaling
Configure **auto scaling for `main-backend`** at minimum. Use CPU utilisation as the scaling metric.

> The other two services are lower priority, but if you have time, apply the same pattern.

#### Alarms
Think about what breaks when a service goes down. At minimum, you should be alerted when:
- A service has **no healthy tasks** behind the load balancer
- A service is **consuming too much CPU or memory**
- **Lambda is throwing errors**
- The **ALB is returning 5xx responses**

> **Hint:** There is a difference between a task that is unhealthy and a task that does not exist at all. Both are problems. Both need different alarms.

#### Designing for tomorrow
This is important. Today you have three services. Next month there may be four. The month after, five.

**The expectation:** adding a fourth ECS service to this stack should take minutes, not hours. Your Terraform (or CDK/CloudFormation) should be structured so that log groups, alarms, and auto scaling are not written from scratch each time.

> **Hint:** What do all three services have in common? If you find yourself writing the same configuration block three times, there is a better way.

---

### 10. Infrastructure as Code

Your deployment must be fully reproducible. Running your code on a fresh AWS account must produce a working stack.

- Tool of your choice: Terraform, AWS CDK, CloudFormation, or a combination
- The code must be clean, readable, and organised
- A colleague should be able to understand your structure without asking you

There is no requirement to use any specific tool. **Justify your choice.**

---

## Testing Your Deployment

Sample invoice PDFs are provided in the `sample-invoices/` folder of this repository:

```
sample-invoices/
├── invoice-acme-corp.pdf
├── invoice-aws-consulting.pdf
├── invoice-cloudhost.pdf
├── invoice-design-studio.pdf
├── invoice-saas-tools.pdf
└── invoice-techpro.pdf
```

Once your stack is deployed:
1. Open the ALB URL in a browser
2. Log in with any email address (e.g. `test@stacknine.com`) and any password
3. Upload one of the sample invoices
4. Wait for the results page to show the extracted invoice data

If the results page shows invoice number, vendor, date, total, and line items — your pipeline is working end-to-end.

---

## Naming Convention

Every AWS resource must follow this naming pattern:

```
hackthon-k9-intern-<your-name>-<resource>
```

**Examples:**
```
hackthon-k9-intern-alice-vpc
hackthon-k9-intern-alice-main-backend-service
hackthon-k9-intern-alice-uploads-bucket
hackthon-k9-intern-alice-db-password          ← SSM parameter name
hackthon-k9-intern-alice-main-backend-ecr     ← ECR repository
```

Resources without the correct prefix will not be evaluated.

---

## Scoring

| Area | What We Look For |
|---|---|
| **End-to-end pipeline works** | Upload a sample invoice, see extracted results on screen |
| **Security** | Encryption, IAM least privilege, network design, SSM usage |
| **Infrastructure as Code** | Reproducible, structured for reuse, adding a 4th service is fast |
| **Observability** | Logs, meaningful alarms, auto scaling on main-backend |
| **Design decisions** | Can you clearly explain every choice you made? |

### Bonus — CI/CD Pipeline

If you implement a **GitHub Actions workflow** that automates the full deployment end-to-end — build Docker images, push to ECR, and deploy to ECS — that will be recognised as additional achievement during the evaluation.

This is not required. But if you get the core infrastructure working with time to spare, this is the next level.

---

## Submission

1. Push your infrastructure code to a GitHub repository
2. Share the repository URL and the running application URL with the evaluator
3. Be ready to walk through your entire architecture — diagram, decisions, tradeoffs

**A well-justified simple design scores higher than a complex design you cannot explain.**
