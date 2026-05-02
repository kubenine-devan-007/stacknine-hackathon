# Hackathon — Task 1: Deploy StackNine Invoice Processor on AWS

**Time allowed:** 2 hours  
**Points:** 100

---

## Scenario

StackNine is a US-based fintech company. All customers are in the United States. The application currently receives around **1,000 requests per month**. You are the first infrastructure engineer on the team.

The application processes invoice PDFs. These are **sensitive financial documents**. Security is not optional — it is a baseline requirement.

Your job is to deploy the full application stack on AWS in a way that is secure, observable, and easy to extend as the product grows.

Read the `README.md` in this repository before you start. It explains the application, the pipeline, and the reasoning behind the design. You are not required to follow our architecture exactly — but if you design something different, you must explain why.

You have your own dedicated AWS account. Work independently.

---

## Naming Convention

Every AWS resource you create must follow this pattern:

```
hackthon-k9-intern-<your-name>-<resource>
```

**Examples:**
```
hackthon-k9-intern-alice-vpc
hackthon-k9-intern-alice-main-backend-cluster
hackthon-k9-intern-alice-uploads-bucket
hackthon-k9-intern-alice-db-password          ← SSM parameter
```

Resources without the correct prefix will not be evaluated.

---

## What You Must Deliver

A fully working deployment where:

1. A user opens the app in a browser, uploads an invoice PDF, and sees the extracted invoice data on screen within ~30 seconds.
2. The full pipeline runs: upload → S3 event → Lambda → extractor → parser → results page.
3. All three application services are running as containers on ECS.
4. Docker images are pushed to **Amazon ECR** and pulled by ECS at deploy time.
5. The database is running and the schema is applied — the application requires PostgreSQL 15. Where and how you run it is your design decision. Be ready to justify it.
6. All infrastructure is deployed as code. Running your code on a clean AWS account must produce a working stack. The tool is your choice — Terraform, CDK, CloudFormation, or any combination.
7. Logs and alarms are in place for all services.

---

## Non-Negotiable Requirements

### Data Security
- Invoice PDFs stored in S3 must be **encrypted at rest**. Choose your encryption approach and justify it.
- The S3 bucket must not be publicly accessible. No exceptions.
- All application configuration and secrets must be sourced from **AWS SSM Parameter Store** at runtime. Nothing sensitive should appear as a plaintext value in a task definition, Lambda environment, or source code.

### IAM
- Every role must follow **least privilege**. Before granting a permission, confirm the service actually needs it.
- Ask yourself: does the parser touch S3? Does the extractor write invoice records? Does Lambda need database access? Grant only what is required.
- Each ECS service must have its own task role. Do not share roles between services.

### Network
- Think carefully about what should and should not be reachable from the internet. Load balancers and application services have different exposure requirements.
- Security groups must be as restrictive as possible. Open only the ports each resource actually uses.

### Infrastructure as Code
- Your code must be reproducible. A colleague should be able to run it on a fresh AWS account and get a working stack.
- **Design for tomorrow:** if a fourth service is added to this application next week, how quickly can you wire it up with the same logging, alarms, and scaling configuration as the existing three? The answer should be: very quickly. Let your code structure reflect that.

### Observability
- Every service must ship logs to CloudWatch with a sensible retention period.
- Auto scaling must be configured for at least the `main-backend` service.
- Think about this: it is 2am and the application is down. What are the first signals you would look for? Those are the alarms you need. Think beyond CPU — consider what happens at the load balancer, at the task level, and at the Lambda level.

---

## Hints

> These are observations, not instructions. Two or three lines each. How you act on them is your decision.

**Region:** All users are in the US. A failure in a single data centre should not take the application down.

**Network design:** Not every component in this stack needs the same level of internet exposure. What does, and what doesn't?

**Encryption:** There is more than one way to encrypt S3 objects. They are not equivalent in terms of key control and auditability.

**IAM depth:** The three services do different things. Their IAM roles should be meaningfully different — not three copies of the same broad policy.

**ECR:** Before your ECS services can run, the images must exist somewhere ECS can pull from. ECR is the natural home. Your infrastructure code should include the repositories.

**Database:** The application needs PostgreSQL 15 with the schema from `db/init.sql`. Where you run it, how you size it, and how the schema gets applied at deploy time are all design decisions. Each has tradeoffs.

**Terraform reusability:** Look at what all three ECS services have in common — cluster, task definition, service, target group, log group, alarms, scaling. If you find yourself writing the same block three times, you are doing it the hard way.

**Lambda reliability:** S3 fires the event once. If the backend is not yet ready, what happens to that upload?

**Alarms — a starting point to think from:** An unhealthy target behind a load balancer and a service with zero running tasks are two different failure modes that need two different signals.

---

## Scoring

| Area | Marks | What We Are Looking For |
|---|---|---|
| **Application works end-to-end** | 25 | Upload a PDF, see extracted results. Full pipeline completes. |
| **Security** | 25 | Encryption, IAM least privilege, network design, SSM usage |
| **Infrastructure as Code** | 20 | Reproducible, clean, structured for future extension |
| **Observability** | 15 | Logs, alarms that matter, auto scaling |
| **Design decisions** | 15 | Can you explain every choice you made, and why? |

---

## Submission

1. Push your infrastructure code to a GitHub repository.
2. Provide the repository link and the public URL of the running application to the evaluator.
3. Be ready to walk through your architecture — diagram, decisions, tradeoffs.

**There is no single correct architecture.** A well-justified simple design scores higher than a complex one you cannot explain.
