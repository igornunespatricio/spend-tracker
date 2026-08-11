#!/usr/bin/env bash
# Creates the S3 bucket used as Terraform remote state backend.
# State locking uses S3 native locking (Terraform >= 1.10, no DynamoDB needed).
# Also sets TF_STATE_BUCKET and AWS_REGION as GitHub repository variables.
# Safe to re-run — checks for existing resources before creating.
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

REGION="${AWS_REGION:-us-east-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || error "Cannot get AWS account ID. Is AWS CLI configured?"

BUCKET_NAME="spend-tracker-tfstate-${ACCOUNT_ID}"

info "Account: ${ACCOUNT_ID} | Region: ${REGION}"
info "Bucket : ${BUCKET_NAME}"
echo

# ── S3 Bucket ────────────────────────────────────────────────────────────────
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  warn "Bucket ${BUCKET_NAME} already exists — skipping creation"
else
  info "Creating S3 bucket..."
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
  info "Bucket created ✓"
fi

info "Enabling server-side encryption..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" },
      "BucketKeyEnabled": true
    }]
  }'

info "Blocking public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# ── GitHub repository variables ───────────────────────────────────────────────
command -v gh &>/dev/null || { warn "GitHub CLI (gh) not found — skipping variable setup. Set manually:"; \
  echo "  TF_STATE_BUCKET = ${BUCKET_NAME}"; echo "  AWS_REGION = ${REGION}"; }

if command -v gh &>/dev/null; then
  GITHUB_REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
  if [[ -z "${GITHUB_REPO}" ]]; then
    warn "Could not detect repository via gh — skipping variable setup. Set manually:"
    echo "  TF_STATE_BUCKET = ${BUCKET_NAME}"
    echo "  AWS_REGION = ${REGION}"
  else
    info "Setting GitHub repository variables for ${GITHUB_REPO}..."
    gh variable set TF_STATE_BUCKET --body "${BUCKET_NAME}" --repo "${GITHUB_REPO}"
    gh variable set AWS_REGION       --body "${REGION}"       --repo "${GITHUB_REPO}"
    info "GitHub variables set ✓"
  fi
fi

# ── Output ────────────────────────────────────────────────────────────────────
echo
echo -e "${GREEN}✅ Terraform state backend is ready!${NC}"
echo
echo "  Bucket     : ${BUCKET_NAME}"
echo "  Region     : ${REGION}"
echo "  Locking    : S3 native (use_lockfile = true — requires Terraform >= 1.10)"
echo
echo "GitHub repository variables set:"
echo "  TF_STATE_BUCKET = ${BUCKET_NAME}"
echo "  AWS_REGION      = ${REGION}"
