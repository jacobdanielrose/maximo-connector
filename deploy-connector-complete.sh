#!/bin/bash

# Complete deployment script for Maximo connector
# Usage: ./deploy-connector-complete.sh

set -e

NAMESPACE="ibm-aiops"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Complete Maximo Connector Deployment"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

# Step 1: Check bundle manifest
echo -e "${BLUE}Step 1: Checking BundleManifest...${NC}"
if oc get bundlemanifest maximo-connector &>/dev/null; then
    STATUS=$(oc get bundlemanifest maximo-connector -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo "BundleManifest exists with status: $STATUS"
    
    if [ "$STATUS" != "Configured" ]; then
        echo -e "${YELLOW}⚠${NC} Bundle is not configured. Redeploying..."
        oc delete bundlemanifest maximo-connector
        sleep 5
        oc apply -f bundlemanifest-maximo.yaml
        echo "Waiting for bundle to be configured (this may take 1-2 minutes)..."
        sleep 30
        NEW_STATUS=$(oc get bundlemanifest maximo-connector -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "New status: $NEW_STATUS"
    else
        echo -e "${GREEN}✓${NC} Bundle is configured"
    fi
else
    echo -e "${YELLOW}⚠${NC} BundleManifest not found. Deploying..."
    oc apply -f bundlemanifest-maximo.yaml
    echo "Waiting for bundle to be configured..."
    sleep 30
fi

echo ""

# Step 2: Check deployment
echo -e "${BLUE}Step 2: Checking Deployment...${NC}"
if oc get deployment ticket-template -n $NAMESPACE &>/dev/null; then
    echo -e "${GREEN}✓${NC} Deployment exists"
    
    REPLICAS=$(oc get deployment ticket-template -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    READY=$(oc get deployment ticket-template -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    echo "Desired replicas: $REPLICAS"
    echo "Ready replicas: $READY"
    
    if [ "$READY" = "0" ] || [ -z "$READY" ]; then
        echo -e "${YELLOW}⚠${NC} No ready replicas. Checking for issues..."
        
        # Check if pods exist
        PODS=$(oc get pods -n $NAMESPACE -l app=ticket-template -o name 2>/dev/null || echo "")
        if [ -z "$PODS" ]; then
            echo -e "${RED}✗${NC} No pods found"
            echo "Checking deployment events..."
            oc describe deployment ticket-template -n $NAMESPACE | grep -A 10 "Events:"
        else
            echo "Pods found:"
            oc get pods -n $NAMESPACE -l app=ticket-template
            echo ""
            echo "Checking pod status..."
            for pod in $PODS; do
                POD_NAME=$(basename "$pod")
                POD_STATUS=$(oc get pod "$POD_NAME" -n $NAMESPACE -o jsonpath='{.status.phase}')
                echo "  $POD_NAME: $POD_STATUS"
                
                if [ "$POD_STATUS" != "Running" ]; then
                    echo "  Checking events..."
                    oc describe pod "$POD_NAME" -n $NAMESPACE | grep -A 10 "Events:" | sed 's/^/    /'
                fi
            done
        fi
    else
        echo -e "${GREEN}✓${NC} Deployment is ready"
    fi
else
    echo -e "${RED}✗${NC} Deployment does not exist"
    echo ""
    echo "The bundle manifest should create the deployment."
    echo "Checking if prereqs are deployed..."
    
    # Check if schema exists
    if oc get connectorschema maximo-connector &>/dev/null; then
        echo -e "${GREEN}✓${NC} ConnectorSchema exists"
    else
        echo -e "${RED}✗${NC} ConnectorSchema missing - deploying..."
        oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml
    fi
    
    echo ""
    echo "Redeploying bundle manifest..."
    oc delete bundlemanifest maximo-connector 2>/dev/null || true
    sleep 5
    oc apply -f bundlemanifest-maximo.yaml
    
    echo "Waiting 60 seconds for deployment to be created..."
    sleep 60
    
    if oc get deployment ticket-template -n $NAMESPACE &>/dev/null; then
        echo -e "${GREEN}✓${NC} Deployment now exists"
    else
        echo -e "${RED}✗${NC} Deployment still not created"
        echo "Check bundle manifest status:"
        oc describe bundlemanifest maximo-connector
    fi
fi

echo ""

# Step 3: Check connector configuration
echo -e "${BLUE}Step 3: Checking ConnectorConfiguration...${NC}"
CONFIGS=$(oc get connectorconfiguration -n $NAMESPACE -o name 2>/dev/null | grep -i maximo || echo "")
if [ -n "$CONFIGS" ]; then
    echo -e "${GREEN}✓${NC} Found connector configuration(s):"
    echo "$CONFIGS" | sed 's/^/  /'
    
    for config in $CONFIGS; do
        CONFIG_NAME=$(basename "$config")
        echo ""
        echo "Configuration: $CONFIG_NAME"
        STATUS=$(oc get "$config" -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        echo "  Status: $STATUS"
    done
else
    echo -e "${YELLOW}⚠${NC} No connector configuration found"
    echo "You need to create an integration through the UI or CLI"
fi

echo ""

# Step 4: Check secrets
echo -e "${BLUE}Step 4: Checking Secrets...${NC}"
CONNECTOR_SECRETS=$(oc get secret -n $NAMESPACE 2>/dev/null | grep "^connector-" | grep -v dockercfg | grep -v bridge || echo "")
if [ -n "$CONNECTOR_SECRETS" ]; then
    echo -e "${GREEN}✓${NC} Found connector secret(s):"
    echo "$CONNECTOR_SECRETS" | sed 's/^/  /'
else
    echo -e "${YELLOW}⚠${NC} No connector secrets found"
    echo "Secrets are created when you create an integration"
fi

echo ""

# Step 5: Summary
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo ""

HAS_BUNDLE=$(oc get bundlemanifest maximo-connector &>/dev/null && echo "yes" || echo "no")
HAS_DEPLOYMENT=$(oc get deployment ticket-template -n $NAMESPACE &>/dev/null && echo "yes" || echo "no")
HAS_PODS=$(oc get pods -n $NAMESPACE -l app=ticket-template &>/dev/null && echo "yes" || echo "no")
HAS_CONFIG=$([ -n "$CONFIGS" ] && echo "yes" || echo "no")

echo "Bundle Manifest: $HAS_BUNDLE"
echo "Deployment: $HAS_DEPLOYMENT"
echo "Pods: $HAS_PODS"
echo "Configuration: $HAS_CONFIG"

echo ""

if [ "$HAS_DEPLOYMENT" = "no" ]; then
    echo -e "${RED}ACTION REQUIRED:${NC} Deployment is missing"
    echo ""
    echo "This usually means:"
    echo "1. Bundle manifest hasn't been deployed"
    echo "2. Bundle manifest failed to create resources"
    echo "3. Image pull issues"
    echo ""
    echo "Steps to fix:"
    echo "1. Check bundle status: oc describe bundlemanifest maximo-connector"
    echo "2. Check for errors in events"
    echo "3. Verify image exists: quay.io/jacobdanielrose/maximo-connector:latest"
    echo "4. Check image pull secret: oc get secret ibm-aiops-pull-secret -n $NAMESPACE"
elif [ "$HAS_PODS" = "no" ]; then
    echo -e "${RED}ACTION REQUIRED:${NC} Pods are not starting"
    echo ""
    echo "Check deployment events:"
    echo "  oc describe deployment ticket-template -n $NAMESPACE"
    echo ""
    echo "Common issues:"
    echo "- Image pull errors"
    echo "- Resource constraints"
    echo "- Missing secrets or configmaps"
elif [ "$HAS_CONFIG" = "no" ]; then
    echo -e "${YELLOW}NEXT STEP:${NC} Create an integration"
    echo ""
    echo "The deployment is ready. Now create an integration:"
    echo "1. Go to AIOps UI → Integrations → Add Integration"
    echo "2. Select: IBM Maximo"
    echo "3. Fill in the form with your Maximo details"
    echo "4. Save"
    echo ""
    echo "After creating the integration, pods will start automatically"
else
    echo -e "${GREEN}✓${NC} Everything looks good!"
    echo ""
    echo "Check pod logs:"
    echo "  oc logs -n $NAMESPACE -l app=ticket-template -f"
fi

echo ""

# Made with Bob
