#!/usr/bin/env bash
# Initialises Terraform with the S3 backend and creates dev/test/prod workspaces.
# Run AFTER 01_create_tfstate_bucket.sh.
# State locking uses S3 native locking (Terraform >= 1.10).
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || error "Cannot get AWS account ID."

BUCKET_NAME="spend-tracker-tfstate-${ACCOUNT_ID}"
TF_DIR="$(cd "$(dirname "$0")/../infrastructure/terraform" && pwd)"

command -v terraform &>/dev/null || error "Terraform not found. Install terraform >= 1.10"

info "Working in: ${TF_DIR}"
cd "${TF_DIR}"

# ── Terraform Init ────────────────────────────────────────────────────────────
info "Running terraform init with S3 backend..."
terraform init \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="key=spend-tracker/terraform.tfstate" \
  -backend-config="region=${REGION}" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true" \
  -reconfigure

info "Init complete ✓"

# ── Workspaces ────────────────────────────────────────────────────────────────
WORKSPACES=("dev" "test" "prod")
EXISTING_WORKSPACES=$(terraform workspace list 2>/dev/null)

for WS in "${WORKSPACES[@]}"; do
  if echo "${EXISTING_WORKSPACES}" | grep -qw "${WS}"; then
    warn "Workspace '${WS}' already exists — skipping"
  else
    info "Creating workspace: ${WS}"
    terraform workspace new "${WS}"
  fi
done

# Switch back to dev as the default working workspace
terraform workspace select dev

echo
echo -e "${GREEN}✅ Terraform workspaces ready!${NC}"
echo
terraform workspace list
echo
echo "To deploy to an environment:"
echo "  terraform workspace select dev"
echo "  terraform plan -var-file=environments/dev/terraform.tfvars"
echo "  terraform apply -var-file=environments/dev/terraform.tfvars"
