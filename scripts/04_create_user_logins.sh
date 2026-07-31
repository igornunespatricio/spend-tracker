#!/usr/bin/env bash
# Creates an initial admin user in the Cognito User Pool for the given environment.
# Usage: ./04_create_user_logins.sh <environment> [email] [temp_password]
# Example: ./04_create_user_logins.sh dev admin@example.com TempPass123!
# Run AFTER terraform apply for the target environment.
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

ENVIRONMENT="${1:-}"
EMAIL="${2:-}"
TEMP_PASSWORD="${3:-TempPass123!}"

[[ -z "${ENVIRONMENT}" ]] && error "Usage: $0 <environment> [email] [temp_password]"
[[ "${ENVIRONMENT}" =~ ^(dev|test|prod)$ ]] || error "Environment must be dev, test or prod"

REGION="${AWS_REGION:-us-east-1}"

# Prompt for email if not provided
if [[ -z "${EMAIL}" ]]; then
  read -rp "Enter admin email for ${ENVIRONMENT}: " EMAIL
fi

[[ "${EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]] || error "Invalid email: ${EMAIL}"

# ── Lookup User Pool ID from SSM or Terraform output ─────────────────────────
info "Looking up Cognito User Pool ID for environment: ${ENVIRONMENT}"

USER_POOL_ID=$(aws ssm get-parameter \
  --name "/spend-tracker/${ENVIRONMENT}/cognito/user-pool-id" \
  --region "${REGION}" \
  --query "Parameter.Value" \
  --output text 2>/dev/null) || {
    error "Cannot find User Pool ID in SSM at /spend-tracker/${ENVIRONMENT}/cognito/user-pool-id\n  Run 'terraform apply' for the ${ENVIRONMENT} environment first."
  }

info "User Pool ID: ${USER_POOL_ID}"

# ── Check if user exists ──────────────────────────────────────────────────────
if aws cognito-idp admin-get-user \
    --user-pool-id "${USER_POOL_ID}" \
    --username "${EMAIL}" \
    --region "${REGION}" 2>/dev/null | grep -q Username; then
  warn "User ${EMAIL} already exists in ${ENVIRONMENT} pool — skipping"
else
  info "Creating user: ${EMAIL}"
  aws cognito-idp admin-create-user \
    --user-pool-id "${USER_POOL_ID}" \
    --username "${EMAIL}" \
    --temporary-password "${TEMP_PASSWORD}" \
    --user-attributes \
      Name=email,Value="${EMAIL}" \
      Name=email_verified,Value=true \
    --message-action SUPPRESS \
    --region "${REGION}"
  info "User created ✓"
fi

# ── Add user to admin group ───────────────────────────────────────────────────
info "Adding ${EMAIL} to 'admins' group..."
aws cognito-idp admin-add-user-to-group \
  --user-pool-id "${USER_POOL_ID}" \
  --username "${EMAIL}" \
  --group-name "admins" \
  --region "${REGION}" 2>/dev/null || warn "Group 'admins' not found — skipping group assignment"

echo
echo -e "${GREEN}✅ User ready!${NC}"
echo "  Environment : ${ENVIRONMENT}"
echo "  Email       : ${EMAIL}"
echo "  Temp Password: ${TEMP_PASSWORD}"
echo
echo "The user will be prompted to set a new password on first login."
