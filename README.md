# 💸 Spend Tracker

A mobile-first spending tracker application running on AWS. Users can manually input spending items or upload photos (receipts/tax notes) to automatically extract and record expenses.

## Architecture Overview

| Layer | Technology |
|---|---|
| Frontend | React + Tailwind CSS (hosted on S3 + CloudFront) |
| API | AWS API Gateway + Lambda (Python) |
| Auth | AWS Cognito User Pools |
| Database | AWS DynamoDB |
| Photo Storage | AWS S3 |
| Photo Processing | AWS SQS → Lambda → Bedrock (Claude) |
| AI Agents | AWS Bedrock Agents with Guardrails |
| IaC | Terraform |
| CI/CD | GitHub Actions (OIDC) |

## Environments

| Environment | Workspace | Purpose |
|---|---|---|
| `dev` | `dev` | Active development |
| `test` | `test` | QA / integration testing |
| `prod` | `prod` | Production |

## Project Structure

```
spend-tracker/
├── .github/
│   ├── copilot-instructions.md     # Copilot AI instructions
│   ├── agents/                     # Copilot agent definitions
│   ├── skills/                     # Copilot skill definitions
│   └── workflows/                  # GitHub Actions CI/CD
├── backend/
│   ├── lambdas/
│   │   ├── api/                    # REST API handlers
│   │   │   ├── spending/           # CRUD for spending items
│   │   │   └── auth/               # Auth helpers
│   │   └── processor/              # Photo processing Lambda
│   ├── agents/                     # Bedrock agent definitions
│   └── guardrails/                 # Bedrock guardrail configs
├── frontend/
│   ├── src/
│   │   ├── pages/                  # Login, Dashboard, ManualInput, PhotoUpload
│   │   ├── components/             # Reusable UI components
│   │   ├── hooks/                  # Custom React hooks
│   │   ├── services/               # API + Auth service clients
│   │   └── types/                  # TypeScript types
│   └── public/
├── infrastructure/
│   └── terraform/
│       ├── modules/                # Reusable Terraform modules
│       │   ├── auth/               # Cognito
│       │   ├── storage/            # DynamoDB + S3
│       │   ├── processing/         # SQS + processor Lambda
│       │   ├── api/                # API Gateway + API Lambdas
│       │   ├── cdn/                # CloudFront
│       │   └── iam/                # IAM roles + OIDC
│       └── environments/           # Per-env tfvars
│           ├── dev/
│           ├── test/
│           └── prod/
├── scripts/                        # One-time setup scripts
│   ├── 01_create_tfstate_bucket.sh
│   ├── 02_create_github_oidc.sh
│   ├── 03_create_tf_workspaces.sh
│   └── 04_create_user_logins.sh
└── docs/
    └── architecture.md
```

## Quick Start

### Prerequisites

- AWS CLI configured with admin permissions
- Terraform >= 1.5
- Node.js >= 20
- Python >= 3.12

### Initial Setup (run once)

```bash
cd scripts

# 1. Create S3 bucket + DynamoDB table for Terraform state
chmod +x *.sh
./01_create_tfstate_bucket.sh

# 2. Create GitHub OIDC provider in AWS
./02_create_github_oidc.sh

# 3. Create Terraform workspaces (dev/test/prod)
./03_create_tf_workspaces.sh

# 4. Create initial application users in Cognito
./04_create_user_logins.sh dev
```

### Deploy Infrastructure

```bash
cd infrastructure/terraform
terraform workspace select dev
terraform init
terraform plan -var-file=environments/dev/terraform.tfvars
terraform apply -var-file=environments/dev/terraform.tfvars
```

### Run Frontend Locally

```bash
cd frontend
npm install
cp .env.example .env.local  # fill in Cognito + API values
npm run dev
```

## CI/CD

Pushes to `develop` → deploys to **dev**.  
Pushes to `main` → deploys to **test**, then waits for manual approval to **prod**.

See `.github/workflows/` for details.

## Photo Processing Flow

1. User uploads photo on `/upload` page and selects a Bedrock model
2. Frontend uploads photo directly to S3 (pre-signed URL)
3. SQS message is enqueued with `{ jobId, s3Key, userId, modelId }`
4. Processor Lambda is triggered, calls Bedrock Claude with the photo
5. Extracted spending items are written to DynamoDB with status `PENDING_REVIEW`
6. Frontend polls for job status and shows extracted items for user review/edit
7. User confirms or edits, then saves → status changes to `CONFIRMED`

## Bedrock Models Available

| Model | ID | Use Case |
|---|---|---|
| Claude 3 Haiku (default) | `anthropic.claude-3-haiku-20240307-v1:0` | Fast, cost-effective |
| Claude 3.5 Haiku | `anthropic.claude-3-5-haiku-20241022-v1:0` | Balanced |
| Claude 3.5 Sonnet | `anthropic.claude-3-5-sonnet-20241022-v2:0` | Higher accuracy |
| Claude 3 Opus | `anthropic.claude-3-opus-20240229-v1:0` | Best quality |
