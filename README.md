# StackNine Invoice Processor

A microservices application that accepts invoice PDF uploads, extracts structured data from them, and presents the results through a web interface.

---

## What This Application Does

Users log in with an email address, upload an invoice PDF, and within a few seconds see the extracted data — invoice number, vendor, date, total, and line items — displayed on screen.

The processing pipeline runs asynchronously. After upload, the user is immediately redirected to a results page that refreshes every three seconds until the job completes.

---

## Architecture

The application is split into three independent Python services:

| Service | Port | Role |
|---|---|---|
| `main-backend` | 8000 | Serves the web UI, handles uploads, orchestrates the pipeline |
| `extractor` | 8001 | Extracts raw text from a PDF using pdfplumber |
| `parser` | 8002 | Parses structured invoice fields from raw text using regex |

All three services share a single PostgreSQL database. The database schema is in `db/init.sql`.

```
                        ┌─────────────┐
          Browser ──────►  main-backend │
                        │   port 8000  │
                        └──────┬──────┘
                               │
               ┌───────────────┼───────────────┐
               ▼               ▼               ▼
         PostgreSQL       extractor         parser
          (port 5432)    (port 8001)      (port 8002)
```

---

## How the Pipeline Works

### Local Mode

```
User uploads PDF
      │
      ▼
main-backend saves file to shared volume
main-backend creates job in DB → gets job_id
main-backend calls POST /process/{job_id} on itself
      │
      ├──► POST /extract on extractor
      │         reads file from shared volume
      │         extracts raw text → saves to DB
      │
      └──► POST /parse on parser
               reads raw text from DB
               parses invoice fields → saves to DB
               marks job status = "done"
      │
      ▼
Results page shows extracted invoice data
```

### Production Mode (AWS)

```
User uploads PDF
      │
      ▼
main-backend saves PDF to S3 uploads bucket
      Key format: {job_id}/{filename}.pdf
main-backend creates job in DB
      │
      ▼
S3 fires ObjectCreated event
      │
      ▼
Lambda receives event
Lambda reads job_id from the S3 object key
Lambda calls POST /process/{job_id} on main-backend via ALB
      │
      ├──► POST /extract on extractor
      │         downloads PDF from S3 to /tmp/
      │         extracts raw text → saves to DB
      │
      └──► POST /parse on parser
               reads raw text from DB
               parses invoice fields → saves to DB
               marks job status = "done"
      │
      ▼
Results page shows extracted invoice data
```

---

## Why We Designed It This Way

### Why S3 for file storage

Fargate containers have ephemeral local storage. A task restart loses any file on disk. S3 is durable, shared across all services, and the natural source for event-driven triggers. Using S3 also removes the need for a shared volume between containers in production.

### Why Lambda between S3 and the backend

The upload HTTP request returns to the user immediately after saving to S3. Processing is decoupled and runs asynchronously. Lambda is the natural bridge between an S3 event and a backend API call — it requires no servers and costs nothing when idle.

We considered placing an SNS topic between S3 and Lambda. SNS adds a retry layer: if Lambda fails or the backend is temporarily unavailable, SNS can attempt redelivery. For 100 users per month this is not strictly necessary, but it is a valid improvement to this architecture if reliability requirements increase.

### Why three separate services

Each service has a different resource profile. The extractor is CPU-intensive. The parser is lightweight. The main-backend handles HTTP connections. Separating them allows each to scale, restart, and fail independently without affecting the others.

### Why SSM Parameter Store for all configuration

Environment variables baked into task definitions are visible in plaintext in the AWS console and in CloudTrail logs. SSM SecureString parameters are encrypted at rest with KMS, access-controlled via IAM, and can be rotated without redeploying a service. All secrets and configuration in this application are read from SSM at container startup.

### Why NLB for the database connection

An NLB provides a stable DNS endpoint for TCP traffic. Rather than hardcoding the EC2 private IP (which changes if the instance is replaced), services connect to the NLB DNS name stored in SSM. The NLB forwards TCP port 5432 to the database instance.

---

## Security Guardrails

These apply to the infrastructure regardless of how it is designed:

- S3 bucket must be private and encrypted at rest using KMS
- SSM parameters containing secrets must use SecureString (KMS-encrypted)
- No application configuration should be hardcoded in task definitions or Lambda — everything comes from SSM
- IAM roles follow least privilege — each service has only the permissions it actually uses
- Services should not be directly reachable from the internet
- The database should not be directly reachable from the internet

---

## Running Locally

```bash
cd hackathon
docker compose up --build
```

| Service | URL |
|---|---|
| Web UI | http://localhost:8000 |
| Extractor API | http://localhost:8001 |
| Parser API | http://localhost:8002 |
| PostgreSQL | localhost:5433 |

### Running Tests

```bash
cd hackathon/extractor  && python -m pytest tests/
cd hackathon/parser     && python -m pytest tests/
cd hackathon/main-backend && python -m pytest tests/
```

### Sample Invoices

Six sample PDFs are in `sample-invoices/` for testing the upload flow.

---

## Repository Structure

```
hackathon/
├── db/
│   └── init.sql              # PostgreSQL schema (4 tables)
├── main-backend/
│   ├── app/                  # FastAPI app, routes, DB layer, config
│   ├── templates/            # HTML templates (login, upload, results, history)
│   ├── Dockerfile
│   └── requirements.txt
├── extractor/
│   ├── app/                  # FastAPI app, PDF extraction, DB layer
│   ├── Dockerfile
│   └── requirements.txt
├── parser/
│   ├── app/                  # FastAPI app, regex parser, DB layer
│   ├── Dockerfile
│   └── requirements.txt
├── lambda/
│   └── handler.py            # S3 event handler → calls /process/{job_id}
├── sample-invoices/          # Six sample PDFs for testing
├── docker-compose.yml        # Local development stack
└── README.md
```

---

## Configuration Reference

All values below are read from SSM Parameter Store at runtime. The SSM paths used by this application:

| Parameter | Type | Description |
|---|---|---|
| `/stacknine/db-host` | String | PostgreSQL hostname or NLB DNS name |
| `/stacknine/db-name` | String | Database name |
| `/stacknine/db-user` | String | Database user |
| `/stacknine/db-password` | SecureString | Database password |
| `/stacknine/main-backend-url` | String | ALB URL — used by Lambda to reach the backend |

The Lambda function reads `/stacknine/main-backend-url` to know where to send the `POST /process/{job_id}` call. This value should be the ALB DNS name.
