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
OIDC_URL="https://token.actions.githubusercontent.com"
# AWS validates GitHub's OIDC provider via its own trusted CA list.
# The thumbprint below is GitHub's current leaf cert thumbprint (updated 2023-06).
# Re-run this script if you see "Not authorized to perform sts:AssumeRoleWithWebIdentity".
OIDC_THUMBPRINT="1c58a3a8518e8759bf075b76b750d4f2df264fcd"
ENVIRONMENTS=("dev" "test" "prod")

command -v gh &>/dev/null || error "GitHub CLI (gh) is required to detect the repository. Install gh and run from the target repo."
GITHUB_REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
[[ -n "${GITHUB_REPO}" ]] || error "Could not detect repository via gh. Run this script from the target repository."

GITHUB_ORG="${GITHUB_REPO%%/*}"
GITHUB_REPO_NAME="${GITHUB_REPO##*/}"

# Resolve numeric IDs for the immutable-ID "sub" format introduced July 2026.
# Capture raw JSON first with || true so pipefail doesn't exit on a 404;
# then extract .id with jq separately.
_org_json="$(gh api "/orgs/${GITHUB_ORG}" 2>/dev/null)" || true
ORG_ID="$(echo "${_org_json}" | jq -r '.id // empty')"
if [[ -z "${ORG_ID}" ]]; then
  _user_json="$(gh api "/users/${GITHUB_ORG}" 2>/dev/null)" \
    || error "Could not resolve GitHub org/user ID for '${GITHUB_ORG}'."
  ORG_ID="$(echo "${_user_json}" | jq -r '.id // empty')"
fi
[[ -n "${ORG_ID}" ]] || error "Could not resolve GitHub org/user ID for '${GITHUB_ORG}'."
_repo_json="$(gh api "/repos/${GITHUB_REPO}" 2>/dev/null)" \
  || error "Could not resolve GitHub repo ID for '${GITHUB_REPO}'."
REPO_ID="$(echo "${_repo_json}" | jq -r '.id // empty')"
[[ -n "${REPO_ID}" ]] || error "Could not resolve GitHub repo ID for '${GITHUB_REPO}'."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || error "Cannot get AWS account ID."

info "Account:  ${ACCOUNT_ID}"
info "Repo:     ${GITHUB_REPO} (repo ID: ${REPO_ID})"
info "Org/User: ${GITHUB_ORG} (org/user ID: ${ORG_ID})"

# ── OIDC Provider ─────────────────────────────────────────────────────────────
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_ARN}" 2>/dev/null | grep -q Url; then
  warn "OIDC provider already exists — updating thumbprint list"
  aws iam update-open-id-connect-provider-thumbprint \
    --open-id-connect-provider-arn "${OIDC_ARN}" \
    --thumbprint-list "${OIDC_THUMBPRINT}"
  info "Thumbprint updated ✓"
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
          "token.actions.githubusercontent.com:sub": [
            "repo:${GITHUB_REPO}:*",
            "repo:${GITHUB_ORG}@${ORG_ID}/${GITHUB_REPO_NAME}@${REPO_ID}:*"
          ]
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
      --description "GitHub Actions OIDC role for spend-tracker ${ENV}" \
      >/dev/null
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
info "Setting GitHub repository secrets via GitHub CLI..."
for ENV in "${ENVIRONMENTS[@]}"; do
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/spend-tracker-github-${ENV}"
  ENV_UPPER=$(echo "${ENV}" | tr '[:lower:]' '[:upper:]')
  gh secret set "AWS_ROLE_ARN_${ENV_UPPER}" --body "${ROLE_ARN}" --repo "${GITHUB_REPO}"
  info "Secret AWS_ROLE_ARN_${ENV_UPPER} set ✓"
done
info "Secrets set successfully ✓"

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
