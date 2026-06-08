#!/bin/bash

# Script to deploy the Maximo connector schema
# This MUST be done before creating integrations through the UI

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Maximo Connector Schema Deployment"
echo "=========================================="
echo ""

# Check if we're logged into OpenShift
if ! oc whoami &>/dev/null; then
    echo -e "${RED}✗${NC} Not logged into OpenShift"
    echo "Please run: oc login <your-cluster>"
    exit 1
fi

echo -e "${GREEN}✓${NC} Logged into OpenShift as: $(oc whoami)"
echo ""

# Deploy the connector schema
echo -e "${BLUE}Step 1: Deploying ConnectorSchema...${NC}"
if oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml; then
    echo -e "${GREEN}✓${NC} ConnectorSchema deployed"
else
    echo -e "${RED}✗${NC} Failed to deploy ConnectorSchema"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 2: Verifying ConnectorSchema...${NC}"
sleep 2

if oc get connectorschema maximo-connector &>/dev/null; then
    echo -e "${GREEN}✓${NC} ConnectorSchema 'maximo-connector' exists"
    
    # Check component name
    COMPONENT_NAME=$(oc get connectorschema maximo-connector -o jsonpath='{.spec.components[0].name}')
    if [ "$COMPONENT_NAME" = "connector" ]; then
        echo -e "${GREEN}✓${NC} Component name is correct: $COMPONENT_NAME"
    else
        echo -e "${RED}✗${NC} Component name is wrong: $COMPONENT_NAME (expected: connector)"
        echo "   This will cause issues. Please check the schema file."
    fi
else
    echo -e "${RED}✗${NC} ConnectorSchema not found"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 3: Deploying other prerequisites...${NC}"

# Deploy topics
if oc apply -f bundle-artifacts/prereqs/topics.yaml; then
    echo -e "${GREEN}✓${NC} Topics deployed"
else
    echo -e "${YELLOW}⚠${NC} Topics deployment had issues (may already exist)"
fi

# Deploy custom images if needed
if [ -f bundle-artifacts/prereqs/custom-images.yaml ]; then
    if oc apply -f bundle-artifacts/prereqs/custom-images.yaml; then
        echo -e "${GREEN}✓${NC} Custom images deployed"
    else
        echo -e "${YELLOW}⚠${NC} Custom images deployment had issues"
    fi
fi

echo ""
echo -e "${BLUE}Step 4: Checking BundleManifest...${NC}"

if oc get bundlemanifest maximo-connector &>/dev/null; then
    STATUS=$(oc get bundlemanifest maximo-connector -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "Configured" ]; then
        echo -e "${GREEN}✓${NC} BundleManifest is Configured"
    else
        echo -e "${YELLOW}⚠${NC} BundleManifest status: $STATUS"
        echo "   Redeploying bundle manifest..."
        oc delete bundlemanifest maximo-connector 2>/dev/null || true
        sleep 5
        oc apply -f bundlemanifest-maximo.yaml
        echo "   Waiting for bundle to be configured (this may take 1-2 minutes)..."
        sleep 10
        NEW_STATUS=$(oc get bundlemanifest maximo-connector -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "   Current status: $NEW_STATUS"
    fi
else
    echo -e "${YELLOW}⚠${NC} BundleManifest not found, deploying..."
    oc apply -f bundlemanifest-maximo.yaml
    echo "   Waiting for bundle to be configured..."
    sleep 10
fi

echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo -e "${GREEN}✓${NC} ConnectorSchema is deployed"
echo -e "${GREEN}✓${NC} Prerequisites are deployed"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Wait 2-3 minutes for the connector pod to start:"
echo "   oc get pods -n <namespace> | grep ticket-template"
echo ""
echo "2. Verify the pod is running:"
echo "   oc get pods -n <namespace> -l app=ticket-template"
echo ""
echo "3. Now create the integration through the AIOps UI:"
echo "   - Go to: Integrations → Add Integration"
echo "   - Select: IBM Maximo"
echo "   - Fill in configuration:"
echo "     • Connection name (unique)"
echo "     • Maximo URL"
echo "     • Authentication (Basic/API Key/OAuth)"
echo "     • Organization ID (e.g., EAGLENA)"
echo "   - Test connection"
echo "   - Save"
echo ""
echo "4. After creating the integration, verify the secret is created:"
echo "   oc get secret connector -n <namespace>"
echo ""
echo "5. Watch connector logs for successful authentication:"
echo "   oc logs -n <namespace> -l app=ticket-template -f"
echo ""
echo "   Look for:"
echo "   ✓ 'starting configuration consume stream'"
echo "   ✓ NO 'UNAUTHENTICATED' errors"
echo ""
echo "=========================================="
echo ""

# Made with Bob
