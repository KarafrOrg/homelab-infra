#!/usr/bin/env bash
set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔍 Validating k3s Cluster Setup${NC}\n"

# Check 1: Ansible installed
echo -n "Checking Ansible... "
if command -v ansible &> /dev/null; then
    ANSIBLE_VERSION=$(ansible --version | head -n1)
    echo -e "${GREEN}✓${NC} $ANSIBLE_VERSION"
else
    echo -e "${RED}✗${NC} Ansible not found"
    exit 1
fi

# Check 2: Required Python modules
echo -n "Checking Python modules... "
MISSING_MODULES=()
for module in ansible kubernetes pyyaml; do
    if ! python3 -c "import $module" 2>/dev/null; then
        MISSING_MODULES+=("$module")
    fi
done

if [ ${#MISSING_MODULES[@]} -eq 0 ]; then
    echo -e "${GREEN}✓${NC} All modules found"
else
    echo -e "${RED}✗${NC} Missing: ${MISSING_MODULES[*]}"
    echo "Install with: pip3 install ${MISSING_MODULES[*]}"
    exit 1
fi

# Check 3: SSH key exists
echo -n "Checking SSH keys... "
if [ -f "generated_keys/ansible_admin_id_rsa" ]; then
    echo -e "${GREEN}✓${NC} SSH keys found"
else
    echo -e "${YELLOW}⚠${NC}  SSH keys not found (run ./scripts/create_keys.sh)"
fi

# Check 4: Inventory file exists
echo -n "Checking inventory... "
if [ -f "inventory.yml" ]; then
    echo -e "${GREEN}✓${NC} inventory.yml found"

    # Check if inventory has dedicated_servers
    if grep -q "dedicated_servers:" inventory.yml; then
        echo -e "  ${GREEN}✓${NC} dedicated_servers group defined"
    else
        echo -e "  ${YELLOW}⚠${NC}  dedicated_servers group not defined"
    fi
else
    echo -e "${RED}✗${NC} inventory.yml not found"
    exit 1
fi

# Check 5: Playbook exists
echo -n "Checking playbook... "
if [ -f "bootstrap/playbooks/create_vms_and_bootstrap_k3s.yml" ]; then
    echo -e "${GREEN}✓${NC} Playbook found"
else
    echo -e "${RED}✗${NC} Playbook not found"
    exit 1
fi

# Check 6: Roles exist
echo -n "Checking roles... "
ROLES_FOUND=true
for role in create_vms bootstrap_k3s; do
    if [ -d "bootstrap/roles/$role" ]; then
        echo -e "  ${GREEN}✓${NC} $role role found"
    else
        echo -e "  ${RED}✗${NC} $role role not found"
        ROLES_FOUND=false
    fi
done

if ! $ROLES_FOUND; then
    exit 1
fi

# Check 7: Test connectivity to servers
echo -n "Testing server connectivity... "
SERVERS=$(grep -A 20 "dedicated_servers:" inventory.yml | grep "ansible_host:" | awk '{print $2}' || true)

if [ -z "$SERVERS" ]; then
    echo -e "${YELLOW}⚠${NC}  No servers configured in inventory"
else
    SUCCESS_COUNT=0
    for server in $SERVERS; do
        if ping -c 1 -W 2 "$server" &> /dev/null; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    done

    if [ "$SUCCESS_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} ($SUCCESS_COUNT servers reachable)"
    else
        echo -e "${YELLOW}⚠${NC}  No servers reachable (may be offline)"
    fi
fi

# Check 8: Test Ansible connectivity
echo -n "Testing Ansible connectivity... "
if [ -f "generated_keys/ansible_admin_id_rsa" ]; then
    if ansible -i inventory.yml dedicated_servers -m ping -o 2>/dev/null | grep -q "SUCCESS"; then
        echo -e "${GREEN}✓${NC} Ansible can reach servers"
    else
        echo -e "${YELLOW}⚠${NC}  Ansible cannot reach servers (check SSH keys)"
    fi
else
    echo -e "${YELLOW}⚠${NC}  SSH keys not available"
fi

# Summary
echo ""
echo -e "${GREEN}✅ Validation Complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Update inventory.yml with your server IPs"
echo "2. Run: ansible-playbook -i inventory.yml bootstrap/playbooks/create_vms_and_bootstrap_k3s.yml"
echo "3. Access cluster: export KUBECONFIG=./kubeconfig-homelab"
echo ""

