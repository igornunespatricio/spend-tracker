# Architecture

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  User (Mobile Browser)                                          │
│  React + Tailwind SPA                                           │
└────────────┬────────────────────────────────────────────────────┘
             │ HTTPS
             ▼
┌─────────────────────────┐
│  CloudFront CDN         │ ← S3 website bucket (static assets)
└────────────┬────────────┘
             │
             ▼ /api/*
┌─────────────────────────┐
│  API Gateway (HTTP API) │ ← JWT authorizer (Cognito)
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  spending-api Lambda    │ ← Python 3.12
│  (CRUD + job creation)  │
└────┬───────────┬────────┘
     │           │
     ▼           ▼
DynamoDB    SQS FIFO Queue
(items)     (processing jobs)
                 │
                 ▼
     ┌─────────────────────────┐
     │  processor Lambda       │ ← Python 3.12, triggered by SQS
     │  - Downloads photo      │
     │  - Calls Bedrock Claude │ ← With Guardrails
     │  - Writes extracted     │
     │    items to DynamoDB    │
     │  - Emits EventBridge    │
     └─────────────────────────┘

Auth: AWS Cognito User Pools
Photo storage: S3 (private, pre-signed URLs for upload)
```

## Data Flow: Manual Entry

```
User fills form → POST /api/spending → Lambda validates → DynamoDB write
                                                         → 200 OK → UI update
```

## Data Flow: Photo Upload

```
User selects photo + model
  → POST /api/jobs          → Lambda → presigned S3 URL + jobId
  → PUT <presigned URL>     → Direct S3 upload (no Lambda involved)
  → POST /api/jobs/{id}/submit → Lambda → SQS message enqueued
  → Poll GET /api/jobs/{id}    → Lambda reads DynamoDB
       ↑ Processor Lambda running ↓
         S3.GetObject → Bedrock.InvokeModel → parse JSON → DynamoDB.UpdateItem (status=PENDING_REVIEW)
  → User reviews extracted items
  → PUT /api/jobs/{id}/confirm → Lambda → writes SpendingItems to DynamoDB
```

## DynamoDB Single-Table Design

```
Table: spend-tracker-<env>-items

SpendingItem:
  PK = USER#<userId>
  SK = SPEND#<ISO8601>#<uuid>
  GSI1PK = <CATEGORY>
  GSI1SK = <ISO8601>

ProcessingJob:
  PK = USER#<userId>
  SK = JOB#<uuid>

GSI1: category-based aggregation queries
```

## Environment Strategy

Three Terraform workspaces share the same codebase but produce completely independent
AWS resources, named `spend-tracker-<workspace>-<resource>`.

```
dev   → spend-tracker-dev-items, spend-tracker-dev-photos, etc.
test  → spend-tracker-test-items, ...
prod  → spend-tracker-prod-items, ...
```

Terraform remote state uses a workspace key prefix so all three workspaces share one S3 bucket
but store state in separate paths.

## CI/CD

```
feature/* → PR checks (fmt, validate, lint, typecheck)
develop   → auto-deploy to dev
main      → auto-deploy to test
           → manual workflow_dispatch to deploy to prod (requires "deploy-prod" confirmation)
```

All GitHub Actions workflows authenticate using OIDC — no long-lived AWS credentials.
Each environment has its own IAM role: `spend-tracker-github-<env>`.

## Security Highlights

- S3 buckets are private; OAC used for CloudFront→S3
- API Gateway requires Cognito JWT on all routes
- DynamoDB queries always scoped to `USER#<userId>` PK
- Processor Lambda only has `bedrock:InvokeModel` (not `bedrock:*`)
- Bedrock Guardrails block PII, off-topic prompts, and harmful content
- SQS queue has DLQ for failed processing retries (max 3)
