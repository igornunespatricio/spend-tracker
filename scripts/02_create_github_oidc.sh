#!/usr/bin/env bash
# Creates the GitHub Actions OIDC provider and per-environment IAM roles in AWS.
# The roles allow GitHub Actions to assume them without long-lived credentials.
# Safe to re-run.
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

REGION="${AWS_REGION:-us-east-1}"
GITHUB_REPO="myusername/spend-tracker"
OIDC_URL="https://token.actions.githubusercontent.com"
OIDC_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
ENVIRONMENTS=("dev" "test" "prod")

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || error "Cannot get AWS account ID."

info "Account: ${ACCOUNT_ID} | Repo: ${GITHUB_REPO}"

# ── OIDC Provider ─────────────────────────────────────────────────────────────
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_ARN}" 2>/dev/null | grep -q Url; then
  warn "OIDC provider already exists — skipping"
else
  info "Creating GitHub OIDC provider..."
  aws iam create-open-id-connect-provider \
    --url "${OIDC_URL}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "${OIDC_THUMBPRINT}"
  info "OIDC provider created ✓"
fi

# ── Per-environment IAM roles ─────────────────────────────────────────────────
for ENV in "${ENVIRONMENTS[@]}"; do
  ROLE_NAME="spend-tracker-github-${ENV}"
  info "Processing role: ${ROLE_NAME}"

  TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF
)

  if aws iam get-role --role-name "${ROLE_NAME}" 2>/dev/null | grep -q RoleName; then
    warn "Role ${ROLE_NAME} already exists — updating trust policy"
    aws iam update-assume-role-policy \
      --role-name "${ROLE_NAME}" \
      --policy-document "${TRUST_POLICY}"
  else
    aws iam create-role \
      --role-name "${ROLE_NAME}" \
      --assume-role-policy-document "${TRUST_POLICY}" \
      --description "GitHub Actions OIDC role for spend-tracker ${ENV}"
    info "Role created ✓"
  fi

  # Attach managed policies (scope-down in production)
  POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"
  if [[ "${ENV}" == "prod" ]]; then
    warn "Attaching AdministratorAccess to prod role — scope this down after initial setup!"
  fi

  aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "${POLICY_ARN}" 2>/dev/null || true

  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
  info "${ENV} role ARN: ${ROLE_ARN}"
done

# ── Set GitHub repository secrets ─────────────────────────────────────────────
echo
if command -v gh &>/dev/null; then
  info "Setting GitHub repository secrets via GitHub CLI..."
  for ENV in "${ENVIRONMENTS[@]}"; do
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/spend-tracker-github-${ENV}"
    ENV_UPPER=$(echo "${ENV}" | tr '[:lower:]' '[:upper:]')
    gh secret set "AWS_ROLE_ARN_${ENV_UPPER}" --body "${ROLE_ARN}" --repo "${GITHUB_REPO}"
    info "Secret AWS_ROLE_ARN_${ENV_UPPER} set ✓"
  done
  info "Secrets set successfully ✓"
else
  warn "GitHub CLI (gh) not found — add these secrets manually in GitHub:"
  for ENV in "${ENVIRONMENTS[@]}"; do
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/spend-tracker-github-${ENV}"
    ENV_UPPER=$(echo "${ENV}" | tr '[:lower:]' '[:upper:]')
    echo "  AWS_ROLE_ARN_${ENV_UPPER} = ${ROLE_ARN}"
  done
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo -e "${GREEN}✅ GitHub OIDC setup complete!${NC}"
echo
echo "IAM roles created:"
for ENV in "${ENVIRONMENTS[@]}"; do
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/spend-tracker-github-${ENV}"
  ENV_UPPER=$(echo "${ENV}" | tr '[:lower:]' '[:upper:]')
  echo "  AWS_ROLE_ARN_${ENV_UPPER} = ${ROLE_ARN}"
done
