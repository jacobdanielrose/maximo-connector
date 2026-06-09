#!/bin/bash

# Script to find and restart the AIOps UI pods
# Usage: ./find-and-restart-ui.sh

NAMESPACE="ibm-aiops"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Finding AIOps UI Pods"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

echo -e "${BLUE}Searching for UI pods...${NC}"
echo ""

# Search for pods with various possible names/labels
echo "Pods with 'ui' in name:"
oc get pods -n $NAMESPACE | grep -i ui | grep -v test | grep -v backup

echo ""
echo "Pods with 'connection' in name:"
oc get pods -n $NAMESPACE | grep -i connection | grep -v test | grep -v backup

echo ""
echo "Pods with 'console' in name:"
oc get pods -n $NAMESPACE | grep -i console | grep -v test | grep -v backup

echo ""
echo "Pods with 'portal' in name:"
oc get pods -n $NAMESPACE | grep -i portal | grep -v test | grep -v backup

echo ""
echo "Pods with 'frontend' in name:"
oc get pods -n $NAMESPACE | grep -i frontend | grep -v test | grep -v backup

echo ""
echo "=========================================="
echo ""
echo "Which pod(s) should be restarted?"
echo "Enter the pod name(s) or deployment name, or 'all' for all UI-related pods:"
read -p "> " POD_INPUT

if [ -z "$POD_INPUT" ]; then
    echo "No input provided. Exiting."
    exit 0
fi

if [ "$POD_INPUT" = "all" ]; then
    echo ""
    echo -e "${YELLOW}Restarting all UI-related pods...${NC}"
    
    # Get all UI-related pods
    UI_PODS=$(oc get pods -n $NAMESPACE -o name | grep -iE "(ui|connection|console|portal|frontend)" | grep -v test | grep -v backup)
    
    if [ -z "$UI_PODS" ]; then
        echo -e "${RED}No UI pods found${NC}"
        exit 1
    fi
    
    echo "$UI_PODS" | while read pod; do
        echo "Deleting: $pod"
        oc delete "$pod" -n $NAMESPACE
    done
else
    # Check if it's a deployment
    if oc get deployment "$POD_INPUT" -n $NAMESPACE &>/dev/null; then
        echo ""
        echo -e "${BLUE}Restarting deployment: $POD_INPUT${NC}"
        oc rollout restart deployment "$POD_INPUT" -n $NAMESPACE
        echo ""
        echo "Waiting for rollout to complete..."
        oc rollout status deployment "$POD_INPUT" -n $NAMESPACE
    # Check if it's a pod name
    elif oc get pod "$POD_INPUT" -n $NAMESPACE &>/dev/null; then
        echo ""
        echo -e "${BLUE}Deleting pod: $POD_INPUT${NC}"
        oc delete pod "$POD_INPUT" -n $NAMESPACE
    # Try as a label selector
    else
        echo ""
        echo -e "${BLUE}Trying as label selector: $POD_INPUT${NC}"
        PODS=$(oc get pods -n $NAMESPACE -l "$POD_INPUT" -o name 2>/dev/null)
        if [ -n "$PODS" ]; then
            echo "$PODS" | while read pod; do
                echo "Deleting: $pod"
                oc delete "$pod" -n $NAMESPACE
            done
        else
            echo -e "${RED}No pods found matching: $POD_INPUT${NC}"
            exit 1
        fi
    fi
fi

echo ""
echo -e "${GREEN}Done!${NC}"
echo ""
echo "Wait 1-2 minutes for pods to restart, then:"
echo "1. Clear your browser cache (Ctrl+Shift+Delete)"
echo "2. Refresh the AIOps UI"
echo "3. Go to Integrations → Add Integration → IBM Maximo"
echo "4. Select authentication type"
echo "5. Fields should now appear"
echo ""

# Made with Bob
