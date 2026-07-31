# Setup Scripts

Run these scripts **once** in order before using Terraform or GitHub Actions.

## Prerequisites

- AWS CLI installed and configured with **AdministratorAccess**
- Terraform >= 1.5 installed
- `jq` installed

## Order of Execution

```bash
chmod +x *.sh

# 1. Create S3 bucket + DynamoDB table for Terraform remote state
./01_create_tfstate_bucket.sh

# 2. Create GitHub OIDC provider + IAM roles in AWS
./02_create_github_oidc.sh

# 3. Initialise Terraform and create workspaces dev/test/prod
./03_create_tf_workspaces.sh

# 4. Bootstrap initial Cognito users per environment
./04_create_user_logins.sh dev
./04_create_user_logins.sh test
./04_create_user_logins.sh prod
```

## Script Details

| Script | What it does |
|---|---|
| `01_create_tfstate_bucket.sh` | Creates `spend-tracker-tfstate-<accountId>` S3 bucket (versioned, encrypted) and `spend-tracker-tfstate-lock` DynamoDB table |
| `02_create_github_oidc.sh` | Creates `token.actions.githubusercontent.com` OIDC provider and per-environment IAM roles (`spend-tracker-github-<env>`) |
| `03_create_tf_workspaces.sh` | Runs `terraform init` with the S3 backend and creates `dev`, `test`, `prod` workspaces |
| `04_create_user_logins.sh` | Creates initial admin user in the Cognito User Pool for the given environment |

## Notes

- All scripts are idempotent — safe to re-run
- The OIDC role ARNs printed by `02_create_github_oidc.sh` must be added as GitHub repository secrets (`AWS_ROLE_ARN_DEV`, `AWS_ROLE_ARN_TEST`, `AWS_ROLE_ARN_PROD`)
- The Cognito User Pool must be deployed (`terraform apply`) before running `04_create_user_logins.sh`
