#!/bin/bash

# Script to reapply the Maximo connector schema with the complete form configuration
# Usage: ./reapply-schema-fix.sh

set -e

NAMESPACE="ibm-aiops"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Reapplying Maximo Connector Schema"
echo "=========================================="
echo ""

echo -e "${BLUE}Step 1: Checking current schema in cluster...${NC}"
CURRENT_FORM=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: username" || echo "0")

if [ "$CURRENT_FORM" -eq "0" ]; then
    echo -e "${RED}✗${NC} Schema in cluster is missing the form fields"
    echo "   This is why the UI doesn't show the authentication fields"
else
    echo -e "${GREEN}✓${NC} Schema has form fields"
fi

echo ""
echo -e "${BLUE}Step 2: Applying the complete schema...${NC}"

if oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml; then
    echo -e "${GREEN}✓${NC} Schema applied successfully"
else
    echo -e "${RED}✗${NC} Failed to apply schema"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 3: Verifying the schema was updated...${NC}"
sleep 2

NEW_FORM=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: username" || echo "0")

if [ "$NEW_FORM" -gt "0" ]; then
    echo -e "${GREEN}✓${NC} Schema now has form fields (found $NEW_FORM username references)"
    
    # Check for all three auth types
    HAS_BASIC=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: basic" || echo "0")
    HAS_APIKEY=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: apikey" || echo "0")
    HAS_OAUTH=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: oauth" || echo "0")
    
    echo -e "${GREEN}✓${NC} Basic auth fields: $HAS_BASIC"
    echo -e "${GREEN}✓${NC} API key fields: $HAS_APIKEY"
    echo -e "${GREEN}✓${NC} OAuth fields: $HAS_OAUTH"
else
    echo -e "${RED}✗${NC} Schema still missing form fields"
    echo ""
    echo "Checking for errors..."
    oc describe connectorschema maximo-connector | grep -A 10 "Events:"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 4: Finding and restarting UI pods...${NC}"

# Try to find UI pods
UI_PODS=$(oc get pods -n $NAMESPACE -o name | grep -iE "(ui|connection|console|portal)" | grep -v test | grep -v backup | head -5)

if [ -n "$UI_PODS" ]; then
    echo "Found UI pods:"
    echo "$UI_PODS" | sed 's/^/  /'
    echo ""
    read -p "Restart these pods? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$UI_PODS" | while read pod; do
            echo "Deleting: $pod"
            oc delete "$pod" -n $NAMESPACE
        done
        echo -e "${GREEN}✓${NC} UI pods restarted"
    else
        echo "Skipped UI restart"
        echo "You can restart manually later with:"
        echo "$UI_PODS" | while read pod; do
            echo "  oc delete $pod -n $NAMESPACE"
        done
    fi
else
    echo -e "${YELLOW}⚠${NC} No UI pods found automatically"
    echo "Please restart UI pods manually:"
    echo "  oc get pods -n $NAMESPACE | grep -i ui"
    echo "  oc delete pod <ui-pod-name> -n $NAMESPACE"
fi

echo ""
echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo ""
echo "1. Wait 1-2 minutes for UI pods to restart"
echo ""
echo "2. Clear your browser cache:"
echo "   - Chrome/Edge: Ctrl+Shift+Delete"
echo "   - Or use Incognito/Private mode"
echo ""
echo "3. Refresh the AIOps UI"
echo ""
echo "4. Go to: Integrations → Add Integration → IBM Maximo"
echo ""
echo "5. Select an authentication type"
echo ""
echo "6. Fields should now appear!"
echo ""
echo "To verify the schema is correct:"
echo "  oc get connectorschema maximo-connector -o yaml | grep -A 20 'id: authType'"
echo ""

# Made with Bob
