# Spend Tracker — GitHub Copilot Instructions

## Project Overview

This is a **mobile-first AWS spending tracker** application. Users log in, manually add spending items or upload photos of receipts/tax notes to be automatically extracted using AWS Bedrock (Claude). All data is stored in DynamoDB and visualized through a React + Tailwind frontend hosted on S3/CloudFront.

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | React 18 + TypeScript + Tailwind CSS + Vite |
| API | AWS API Gateway (HTTP API) + Lambda (Python 3.12) |
| Auth | AWS Cognito User Pools |
| Database | AWS DynamoDB (single-table design) |
| Photo Storage | AWS S3 (private bucket, pre-signed URLs) |
| Photo Queue | AWS SQS (FIFO queue) |
| AI Processing | AWS Bedrock (Claude — model selectable by user) |
| AI Agents | AWS Bedrock Agents with action groups |
| Guardrails | AWS Bedrock Guardrails (content filtering) |
| IaC | Terraform >= 1.5 (workspaces: dev/test/prod) |
| CI/CD | GitHub Actions + AWS OIDC (no long-lived credentials) |

## Repository Layout

```
.github/copilot-instructions.md    ← you are here
.github/agents/                    ← Copilot agent prompt files
.github/skills/                    ← Copilot skill definitions
.github/workflows/                 ← GitHub Actions pipelines
backend/lambdas/api/spending/      ← CRUD Lambda (Python)
backend/lambdas/api/auth/          ← Auth helper Lambda (Python)
backend/lambdas/processor/         ← Photo processor Lambda (Python)
backend/agents/                    ← Bedrock agent JSON definitions
backend/guardrails/                ← Bedrock guardrail JSON configs
frontend/src/pages/                ← Login, Dashboard, ManualInput, PhotoUpload
frontend/src/components/           ← Shared UI components
frontend/src/hooks/                ← Custom React hooks
frontend/src/services/             ← api.ts, auth.ts
frontend/src/types/                ← TypeScript type definitions
infrastructure/terraform/          ← All IaC lives here
scripts/                           ← One-time setup shell scripts
docs/                              ← Architecture documentation
```

## Coding Conventions

### Python (Lambdas)

- Python **3.12**, type hints on all functions
- Return `{ "statusCode": int, "headers": {...}, "body": json.dumps({...}) }` from API handlers
- Use `boto3` for AWS SDK calls; use `from __future__ import annotations`
- Always validate input and return appropriate HTTP status codes (400/401/403/404/500)
- Use `decimal.Decimal` for monetary amounts (never `float`)
- Environment variables for all config (never hardcode ARNs/table names/region)
- Lambda handler signature: `def handler(event: dict, context: Any) -> dict`
- Structured logging with `json` to stdout; include `correlation_id`, `user_id`, `environment`
- Each Lambda directory has its own `requirements.txt`

### TypeScript / React (Frontend)

- React **18** functional components with hooks only (no class components)
- TypeScript strict mode; explicit return types on all exported functions
- Tailwind CSS for all styling; no inline styles, no CSS modules
- Mobile-first responsive design — every component must work on 375px screens
- Use `@tanstack/react-query` for server state (data fetching, caching, mutations)
- Use `zustand` for client state (auth session, UI state)
- Use `react-router-dom` v6 for routing
- Use `react-hook-form` + `zod` for all forms
- Use `recharts` for charts/graphs
- Named exports for components, default export for pages
- Component files: `PascalCase.tsx`; hook files: `useCamelCase.ts`; service files: `camelCase.ts`

### Terraform

- Use Terraform **workspaces** (`dev` / `test` / `prod`) to manage environments
- `terraform.workspace` drives all environment-specific naming: `spend-tracker-${terraform.workspace}-<resource>`
- Remote state in S3 with DynamoDB locking
- All resources tagged with `{ Environment, Project, ManagedBy = "terraform" }`
- Modules receive environment name via `var.environment`
- GitHub OIDC provider and CI assume-role IAM roles are bootstrap resources managed by `scripts/02_create_github_oidc.sh` (not Terraform modules)

### DynamoDB Single-Table Design

Table name: `spend-tracker-<env>-items`

| Entity | PK | SK | Attributes |
|---|---|---|---|
| SpendingItem | `USER#<userId>` | `SPEND#<ISO8601>#<uuid>` | amount (Decimal), category, location, description, source, photoKey, status |
| ProcessingJob | `USER#<userId>` | `JOB#<jobId>` | s3Key, modelId, status, extractedItems, createdAt, updatedAt |

GSI: `GSI1` — PK: `category`, SK: `createdAt` — for category aggregations.

### Shell Scripts

- `#!/usr/bin/env bash` shebang + `set -euo pipefail`
- Color-coded output: green for success, red for errors
- Scripts are idempotent where possible
- Scripts accept environment as `$1` argument when relevant

## Environment Variables

### Lambda

```
ENVIRONMENT, TABLE_NAME, PHOTOS_BUCKET, PROCESSING_QUEUE_URL,
COGNITO_USER_POOL_ID, REGION, ALLOWED_MODELS
```

### Frontend (`.env.local`)

```
VITE_API_URL, VITE_COGNITO_USER_POOL_ID, VITE_COGNITO_CLIENT_ID, VITE_REGION
```

## Key Workflows

### Manual Spend Entry

`POST /api/spending` → spending Lambda validates + writes to DynamoDB

### Photo Upload Flow

1. `POST /api/jobs` → returns pre-signed S3 URL + `jobId`
2. Frontend PUTs photo to S3
3. `POST /api/jobs/{jobId}/submit` → Lambda enqueues SQS message
4. Processor Lambda → Bedrock → writes extracted items to DynamoDB
5. Frontend polls `GET /api/jobs/{jobId}` until `PENDING_REVIEW`
6. User reviews/edits → `PUT /api/jobs/{jobId}/confirm` → saves `SpendingItem` records

## Bedrock Models Available

| Display Name | Model ID |
|---|---|
| Claude 3 Haiku (default) | `anthropic.claude-3-haiku-20240307-v1:0` |
| Claude 3.5 Haiku | `anthropic.claude-3-5-haiku-20241022-v1:0` |
| Claude 3.5 Sonnet v2 | `anthropic.claude-3-5-sonnet-20241022-v2:0` |
| Claude 3 Opus | `anthropic.claude-3-opus-20240229-v1:0` |

## Security Requirements

- No AWS credentials in code or GitHub secrets (OIDC only)
- DynamoDB items always scoped to `userId` from JWT
- S3 photo bucket is private; use pre-signed URLs
- API Gateway validates Cognito JWT on every request
- Bedrock Guardrails block PII extraction and off-topic prompts
- Lambdas use least-privilege IAM roles

## CI/CD

| Branch | Action |
|---|---|
| `feature/*`, `fix/*` | PR checks: Terraform fmt/validate, lint, typecheck |
| `develop` | Deploy to `dev` |
| `main` | Deploy to `test`; manual approval for `prod` |

## Guardrails and Hooks

- **Bedrock Guardrails**: applied to all Bedrock calls; block harmful content and PII
- **EventBridge Hooks**: processor Lambda emits `PROCESSING_STARTED`, `EXTRACTION_COMPLETE`, `PROCESSING_FAILED`
- **Copilot Agents**: see `.github/agents/` for spending-assistant and architecture-reviewer
