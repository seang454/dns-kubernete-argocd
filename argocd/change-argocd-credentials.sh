#!/bin/bash

# ArgoCD Credentials Update Script
# Usage: ./argocd-update-credentials.sh <username> <password> [namespace]

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default namespace
NAMESPACE="${3:-argocd}"
USERNAME=$1
PASSWORD=$2
TEMP_DIR="/tmp/argocd-update-$$"

# Validation
if [ $# -lt 2 ]; then
    echo -e "${RED}❌ Error: Missing arguments${NC}"
    echo -e "${YELLOW}Usage: $0 <username> <password> [namespace]${NC}"
    echo -e "${YELLOW}Example: $0 seang seang0405 argocd${NC}"
    exit 1
fi

# Functions
print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  ArgoCD Credentials Update Script      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}► Step $1: $2${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

trap cleanup EXIT

# Start
print_header

echo -e "${YELLOW}Configuration:${NC}"
echo "  Username: ${CYAN}$USERNAME${NC}"
echo "  Namespace: ${CYAN}$NAMESPACE${NC}"
echo ""

# Step 1: Verify kubectl
print_step "1" "Verifying kubectl installation"
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found"
    exit 1
fi
print_success "kubectl is installed"

# Step 2: Verify htpasswd
print_step "2" "Verifying htpasswd installation"
if ! command -v htpasswd &> /dev/null; then
    print_warning "htpasswd not found, installing apache2-utils"
    sudo apt-get update -qq && sudo apt-get install -y -qq apache2-utils
    print_success "apache2-utils installed"
else
    print_success "htpasswd is installed"
fi

# Step 3: Check namespace exists
print_step "3" "Checking namespace: $NAMESPACE"
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi
print_success "Namespace '$NAMESPACE' exists"

# Step 4: Check argocd-secret exists
print_step "4" "Checking argocd-secret in namespace"
if ! kubectl -n "$NAMESPACE" get secret argocd-secret &> /dev/null; then
    print_error "Secret 'argocd-secret' not found in namespace '$NAMESPACE'"
    exit 1
fi
print_success "argocd-secret found"

# Step 5: Create temp directory
print_step "5" "Creating temporary working directory"
mkdir -p "$TEMP_DIR"
print_success "Temp directory created: $TEMP_DIR"

# Step 6: Generate password hash
print_step "6" "Generating bcrypt password hash"
HASH=$(htpasswd -bnBC 10 "" "$PASSWORD" | tr -d ':\n' | sed 's/$2y/$2a/')
if [ -z "$HASH" ]; then
    print_error "Failed to generate password hash"
    exit 1
fi
print_success "Password hash generated"
echo -e "  Hash: ${CYAN}$HASH${NC}"

# Step 7: Convert to base64
print_step "7" "Encoding hash to base64"
HASH_BASE64=$(echo -n "$HASH" | base64 -w 0)
if [ -z "$HASH_BASE64" ]; then
    print_error "Failed to encode to base64"
    exit 1
fi
print_success "Base64 encoding completed"
echo -e "  Base64: ${CYAN}${HASH_BASE64:0:50}...${NC}"

# Step 8: Backup current secret
print_step "8" "Backing up current secret"
BACKUP_FILE="$TEMP_DIR/argocd-secret-backup-$(date +%Y%m%d-%H%M%S).yaml"
if kubectl -n "$NAMESPACE" get secret argocd-secret -o yaml > "$BACKUP_FILE"; then
    print_success "Backup created: $BACKUP_FILE"
else
    print_error "Failed to backup secret"
    exit 1
fi

# Step 9: Update ConfigMap with new account
print_step "9" "Updating ConfigMap to enable account"
if kubectl -n "$NAMESPACE" patch configmap argocd-cm \
  --type merge \
  -p '{"data": {"accounts.'"$USERNAME"'": "apiKey,login"}}' &> /dev/null; then
    print_success "ConfigMap updated with account: $USERNAME"
else
    print_warning "ConfigMap update failed or account already exists"
fi

# Step 10: Prepare updated secret
print_step "10" "Preparing updated secret"
UPDATED_SECRET="$TEMP_DIR/argocd-secret-updated.yaml"
cp "$BACKUP_FILE" "$UPDATED_SECRET"

# Check if password entry exists
if grep -q "^\s*$USERNAME\.password:" "$UPDATED_SECRET"; then
    print_warning "Password entry exists, replacing it"
    sed -i "s/^\(\s*\)$USERNAME\.password:.*$/\1$USERNAME.password: $HASH_BASE64/" "$UPDATED_SECRET"
else
    print_warning "Password entry does not exist, adding it"
    sed -i "/^data:$/a\\  $USERNAME.password: $HASH_BASE64" "$UPDATED_SECRET"
fi
print_success "Secret prepared for update"

# Step 11: Apply updated secret
print_step "11" "Applying updated secret to cluster"
if kubectl apply -f "$UPDATED_SECRET" &> /dev/null; then
    print_success "Secret applied successfully"
else
    print_error "Failed to apply secret"
    echo -e "${YELLOW}Restore from backup:${NC}"
    echo "  kubectl apply -f $BACKUP_FILE"
    exit 1
fi

# Step 12: Verify secret update
print_step "12" "Verifying secret update"
CURRENT_PASSWORD=$(kubectl -n "$NAMESPACE" get secret argocd-secret -o jsonpath="{.data.$USERNAME\.password}" 2>/dev/null || echo "")
if [ "$CURRENT_PASSWORD" = "$HASH_BASE64" ]; then
    print_success "Secret verified in cluster"
else
    print_error "Secret verification failed"
    echo -e "${YELLOW}Restore from backup:${NC}"
    echo "  kubectl apply -f $BACKUP_FILE"
    exit 1
fi

# Step 13: Restart ArgoCD
print_step "13" "Restarting ArgoCD server"
if kubectl -n "$NAMESPACE" rollout restart deployment/argocd-server &> /dev/null; then
    print_success "ArgoCD restart initiated"
else
    print_error "Failed to restart ArgoCD"
    exit 1
fi

# Step 14: Wait for restart
print_step "14" "Waiting for ArgoCD to restart"
echo -e "${YELLOW}This may take 30-60 seconds...${NC}"
if kubectl -n "$NAMESPACE" rollout status deployment/argocd-server --timeout=3m &> /dev/null; then
    print_success "ArgoCD restarted successfully"
else
    print_warning "ArgoCD restart timeout (may still be restarting)"
fi

# Step 15: Final verification
print_step "15" "Performing final verification"
sleep 3
if kubectl -n "$NAMESPACE" get secret argocd-secret -o yaml | grep -q "$USERNAME.password"; then
    print_success "Credentials verified in secret"
else
    print_error "Credentials not found in secret"
    exit 1
fi

# Success message
echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ✓ Update Completed Successfully!      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}New Credentials:${NC}"
echo -e "  Username: ${GREEN}$USERNAME${NC}"
echo -e "  Password: ${GREEN}$PASSWORD${NC}"
echo ""

echo -e "${YELLOW}How to Access ArgoCD:${NC}"
echo ""
echo -e "${CYAN}Option 1 - Local Port Forward:${NC}"
echo "  kubectl port-forward svc/argocd-server -n $NAMESPACE 8080:80"
echo "  Then visit: http://localhost:8080"
echo ""
echo -e "${CYAN}Option 2 - Via Domain:${NC}"
echo "  https://argocd.seang.shop"
echo ""

echo -e "${YELLOW}Important Files:${NC}"
echo "  Backup: $BACKUP_FILE"
echo "  Updated: $UPDATED_SECRET"
echo ""

echo -e "${YELLOW}To Restore from Backup (if needed):${NC}"
echo "  kubectl apply -f $BACKUP_FILE"
echo ""

echo -e "${GREEN}Ready to log in! 🎉${NC}"
echo ""