#!/bin/bash

# Script to verify schema deployment and force UI refresh
# Usage: ./verify-and-fix-ui.sh <namespace>

set -e

NAMESPACE=${1:-"ibm-aiops"}
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Maximo Connector UI Verification & Fix"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

# Step 1: Verify schema exists
echo -e "${BLUE}Step 1: Verifying ConnectorSchema...${NC}"
if oc get connectorschema maximo-connector &>/dev/null; then
    echo -e "${GREEN}✓${NC} ConnectorSchema 'maximo-connector' exists"
    
    # Check display name
    DISPLAY_NAME=$(oc get connectorschema maximo-connector -o jsonpath='{.spec.uiSchema.displayName}' 2>/dev/null || echo "")
    if [ -n "$DISPLAY_NAME" ]; then
        echo -e "${GREEN}✓${NC} Display name: $DISPLAY_NAME"
    else
        echo -e "${RED}✗${NC} No display name found in schema"
    fi
    
    # Check type
    TYPE=$(oc get connectorschema maximo-connector -o jsonpath='{.spec.uiSchema.type}' 2>/dev/null || echo "")
    if [ -n "$TYPE" ]; then
        echo -e "${GREEN}✓${NC} Type: $TYPE"
    else
        echo -e "${RED}✗${NC} No type found in schema"
    fi
else
    echo -e "${RED}✗${NC} ConnectorSchema 'maximo-connector' NOT FOUND"
    echo ""
    echo "The schema must be deployed first. Run:"
    echo "  oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml"
    exit 1
fi

echo ""

# Step 2: Check bundle manifest
echo -e "${BLUE}Step 2: Checking BundleManifest...${NC}"
if oc get bundlemanifest maximo-connector &>/dev/null; then
    STATUS=$(oc get bundlemanifest maximo-connector -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "Configured" ]; then
        echo -e "${GREEN}✓${NC} BundleManifest status: Configured"
    else
        echo -e "${YELLOW}⚠${NC} BundleManifest status: $STATUS"
        echo "   Waiting for bundle to be configured..."
    fi
else
    echo -e "${YELLOW}⚠${NC} BundleManifest not found"
fi

echo ""

# Step 3: Find and restart UI pods
echo -e "${BLUE}Step 3: Restarting UI pods...${NC}"

# Try different possible UI pod labels
UI_LABELS=(
    "app.kubernetes.io/name=aiops-connections-ui"
    "app=aiops-connections-ui"
    "component=aiops-connections-ui"
    "app.kubernetes.io/component=connections-ui"
)

UI_FOUND=false
for label in "${UI_LABELS[@]}"; do
    UI_PODS=$(oc get pods -n $NAMESPACE -l "$label" -o name 2>/dev/null || true)
    if [ -n "$UI_PODS" ]; then
        echo -e "${GREEN}✓${NC} Found UI pods with label: $label"
        echo "$UI_PODS" | while read pod; do
            echo "   Deleting: $pod"
            oc delete "$pod" -n $NAMESPACE
        done
        UI_FOUND=true
        break
    fi
done

if [ "$UI_FOUND" = false ]; then
    echo -e "${YELLOW}⚠${NC} Could not find UI pods with standard labels"
    echo "   Searching for any pods with 'ui' or 'connection' in name..."
    
    ALL_UI_PODS=$(oc get pods -n $NAMESPACE -o name | grep -iE "(connection|ui)" | grep -v "test" || true)
    if [ -n "$ALL_UI_PODS" ]; then
        echo "   Found possible UI pods:"
        echo "$ALL_UI_PODS" | sed 's/^/   /'
        echo ""
        read -p "   Delete these pods to refresh UI? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$ALL_UI_PODS" | while read pod; do
                oc delete "$pod" -n $NAMESPACE
            done
        fi
    else
        echo -e "${RED}✗${NC} No UI pods found"
    fi
fi

echo ""

# Step 4: Wait for UI to restart
if [ "$UI_FOUND" = true ]; then
    echo -e "${BLUE}Step 4: Waiting for UI to restart...${NC}"
    echo "   This may take 30-60 seconds..."
    sleep 10
    
    for i in {1..12}; do
        for label in "${UI_LABELS[@]}"; do
            READY=$(oc get pods -n $NAMESPACE -l "$label" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
            if [ "$READY" = "true" ]; then
                echo -e "${GREEN}✓${NC} UI pod is ready"
                break 2
            fi
        done
        echo "   Waiting... ($i/12)"
        sleep 5
    done
fi

echo ""

# Step 5: Check connector schema in API
echo -e "${BLUE}Step 5: Verifying schema is accessible via API...${NC}"

# Get the schema as JSON to verify it's complete
SCHEMA_JSON=$(oc get connectorschema maximo-connector -o json 2>/dev/null || echo "")
if [ -n "$SCHEMA_JSON" ]; then
    # Check for required fields
    HAS_UISCHEMA=$(echo "$SCHEMA_JSON" | grep -c "uiSchema" || true)
    HAS_FORM=$(echo "$SCHEMA_JSON" | grep -c "\"form\":" || true)
    HAS_AUTHTYPE=$(echo "$SCHEMA_JSON" | grep -c "authType" || true)
    
    if [ "$HAS_UISCHEMA" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Schema has uiSchema section"
    else
        echo -e "${RED}✗${NC} Schema missing uiSchema section"
    fi
    
    if [ "$HAS_FORM" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Schema has form configuration"
    else
        echo -e "${RED}✗${NC} Schema missing form configuration"
    fi
    
    if [ "$HAS_AUTHTYPE" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Schema has authType field"
    else
        echo -e "${RED}✗${NC} Schema missing authType field"
    fi
else
    echo -e "${RED}✗${NC} Could not retrieve schema JSON"
fi

echo ""

# Step 6: Instructions
echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo ""
echo "1. Wait 2-3 minutes for UI to fully restart and load schemas"
echo ""
echo "2. Clear your browser cache:"
echo "   - Chrome/Edge: Ctrl+Shift+Delete"
echo "   - Firefox: Ctrl+Shift+Delete"
echo "   - Or use Incognito/Private mode"
echo ""
echo "3. Access AIOps UI and try again:"
echo "   - Go to: Integrations → Add Integration"
echo "   - Search for: Maximo"
echo "   - You should see: IBM Maximo"
echo ""
echo "4. If still not visible, check:"
echo "   - Browser console (F12) for JavaScript errors"
echo "   - UI pod logs:"
echo "     oc logs -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui --tail=100"
echo ""
echo "5. Verify the schema is correct:"
echo "   oc get connectorschema maximo-connector -o yaml | less"
echo ""
echo "=========================================="
echo ""

# Made with Bob
