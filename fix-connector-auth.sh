#!/bin/bash

# Script to fix connector authentication issues
# Usage: ./fix-connector-auth.sh <namespace>

set -e

NAMESPACE=${1:-"ibm-aiops"}
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Connector Authentication Fix Script"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

# Check if connector secret exists
echo -e "${BLUE}Step 1: Checking connector secret...${NC}"
if oc get secret connector -n "$NAMESPACE" &>/dev/null; then
    echo -e "${YELLOW}⚠${NC} Connector secret exists"
    
    # Check if it has the required keys
    HAS_CLIENT_ID=$(oc get secret connector -n "$NAMESPACE" -o jsonpath='{.data.client-id}' 2>/dev/null)
    HAS_CLIENT_SECRET=$(oc get secret connector -n "$NAMESPACE" -o jsonpath='{.data.client-secret}' 2>/dev/null)
    
    if [ -z "$HAS_CLIENT_ID" ] || [ -z "$HAS_CLIENT_SECRET" ]; then
        echo -e "${RED}✗${NC} Secret is missing required keys (client-id or client-secret)"
        echo "   This secret needs to be recreated."
    else
        echo -e "${GREEN}✓${NC} Secret has required keys"
        echo "   However, the credentials may be invalid or out of sync."
    fi
    
    echo ""
    echo -e "${YELLOW}Recommended action:${NC} Delete and recreate the integration"
    echo ""
    read -p "Do you want to delete the connector secret now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting connector secret..."
        oc delete secret connector -n "$NAMESPACE"
        echo -e "${GREEN}✓${NC} Secret deleted"
        echo ""
        echo "Now you need to:"
        echo "1. Go to AIOps UI → Integrations"
        echo "2. Find and delete the Maximo integration"
        echo "3. Create a new Maximo integration"
        echo "4. Fill in all configuration details"
        echo "5. Test and save"
    else
        echo "Skipping secret deletion."
    fi
else
    echo -e "${RED}✗${NC} Connector secret does not exist"
    echo "   This is the root cause of the authentication error."
    echo ""
    echo -e "${YELLOW}Action required:${NC}"
    echo "1. Go to AIOps UI → Integrations"
    echo "2. Click 'Add Integration'"
    echo "3. Select 'IBM Maximo'"
    echo "4. Complete the configuration form"
    echo "5. Test and save the connection"
    echo ""
    echo "The secret will be automatically created when you save the integration."
fi

echo ""
echo -e "${BLUE}Step 2: Checking connector configuration...${NC}"
CONNECTOR_CONFIGS=$(oc get connectorconfiguration -n "$NAMESPACE" -o name 2>/dev/null | grep -i maximo || true)

if [ -z "$CONNECTOR_CONFIGS" ]; then
    echo -e "${RED}✗${NC} No Maximo connector configuration found"
    echo "   You need to create an integration through the AIOps UI."
else
    echo -e "${GREEN}✓${NC} Found connector configuration(s):"
    echo "$CONNECTOR_CONFIGS" | sed 's/^/   /'
    echo ""
    
    # Check if there are multiple configs
    CONFIG_COUNT=$(echo "$CONNECTOR_CONFIGS" | wc -l)
    if [ "$CONFIG_COUNT" -gt 1 ]; then
        echo -e "${YELLOW}⚠${NC} Multiple configurations found. This may cause conflicts."
        echo "   Consider deleting duplicates."
    fi
    
    # Check status of each config
    for config in $CONNECTOR_CONFIGS; do
        CONFIG_NAME=$(basename "$config")
        STATUS=$(oc get "$config" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$STATUS" = "True" ]; then
            echo -e "   ${GREEN}✓${NC} $CONFIG_NAME: Ready"
        else
            echo -e "   ${RED}✗${NC} $CONFIG_NAME: Not Ready (Status: $STATUS)"
        fi
    done
fi

echo ""
echo -e "${BLUE}Step 3: Checking connector pod...${NC}"
CONNECTOR_POD=$(oc get pod -n "$NAMESPACE" -l app=ticket-template -o name 2>/dev/null | head -1)

if [ -n "$CONNECTOR_POD" ]; then
    POD_NAME=$(basename "$CONNECTOR_POD")
    echo -e "${GREEN}✓${NC} Connector pod: $POD_NAME"
    
    # Check if pod is running
    POD_STATUS=$(oc get "$CONNECTOR_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "${GREEN}✓${NC} Pod is running"
        
        # Check for recent auth errors
        echo ""
        echo "Checking for authentication errors in logs..."
        AUTH_ERRORS=$(oc logs "$CONNECTOR_POD" -n "$NAMESPACE" --tail=50 2>/dev/null | grep -c "UNAUTHENTICATED" || true)
        
        if [ "$AUTH_ERRORS" -gt 0 ]; then
            echo -e "${RED}✗${NC} Found $AUTH_ERRORS authentication errors in recent logs"
            echo ""
            echo "Most recent error:"
            oc logs "$CONNECTOR_POD" -n "$NAMESPACE" --tail=50 2>/dev/null | grep "UNAUTHENTICATED" | tail -1 | sed 's/^/   /'
        else
            echo -e "${GREEN}✓${NC} No authentication errors in recent logs"
        fi
    else
        echo -e "${RED}✗${NC} Pod status: $POD_STATUS"
    fi
    
    echo ""
    read -p "Do you want to restart the connector pod? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Restarting connector pod..."
        oc delete "$CONNECTOR_POD" -n "$NAMESPACE"
        echo -e "${GREEN}✓${NC} Pod deleted (will be recreated automatically)"
        echo "Wait 30 seconds for the new pod to start, then check logs:"
        echo "   oc logs -n $NAMESPACE -l app=ticket-template -f"
    fi
else
    echo -e "${RED}✗${NC} Connector pod not found"
    echo "   Check deployment: oc get deployment ticket-template -n $NAMESPACE"
fi

echo ""
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo ""

if [ -z "$CONNECTOR_CONFIGS" ]; then
    echo -e "${RED}ACTION REQUIRED:${NC} Create integration through AIOps UI"
    echo ""
    echo "Steps:"
    echo "1. Open AIOps UI → Integrations"
    echo "2. Click 'Add Integration'"
    echo "3. Select 'IBM Maximo'"
    echo "4. Fill in configuration:"
    echo "   - Connection name (unique)"
    echo "   - Maximo URL"
    echo "   - Authentication (Basic/API Key/OAuth)"
    echo "   - Organization ID (e.g., EAGLENA)"
    echo "5. Test connection"
    echo "6. Save"
elif ! oc get secret connector -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}ACTION REQUIRED:${NC} Recreate integration through AIOps UI"
    echo ""
    echo "The connector configuration exists but the secret is missing."
    echo "This usually means the integration was partially deleted."
    echo ""
    echo "Steps:"
    echo "1. Delete existing configuration:"
    for config in $CONNECTOR_CONFIGS; do
        echo "   oc delete $config -n $NAMESPACE"
    done
    echo "2. Create new integration through AIOps UI"
else
    echo -e "${YELLOW}LIKELY FIX:${NC} Delete and recreate integration"
    echo ""
    echo "The secret exists but credentials are invalid/out of sync."
    echo ""
    echo "Steps:"
    echo "1. Delete integration in AIOps UI (or via CLI):"
    for config in $CONNECTOR_CONFIGS; do
        echo "   oc delete $config -n $NAMESPACE"
    done
    echo "2. Verify secret is deleted:"
    echo "   oc get secret connector -n $NAMESPACE"
    echo "3. Create new integration through AIOps UI"
fi

echo ""
echo "For detailed troubleshooting: GRPC-AUTH-TROUBLESHOOTING.md"
echo "For quick reference: QUICK-FIX-GUIDE.md"
echo ""

# Made with Bob
