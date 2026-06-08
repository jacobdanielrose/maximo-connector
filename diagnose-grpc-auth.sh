#!/bin/bash

# Diagnostic script for gRPC authentication issues
# Usage: ./diagnose-grpc-auth.sh <namespace>

set -e

NAMESPACE=${1:-"ibm-aiops"}
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "gRPC Authentication Diagnostic Tool"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if namespace exists
echo "1. Checking namespace..."
if oc get namespace "$NAMESPACE" &>/dev/null; then
    print_status 0 "Namespace '$NAMESPACE' exists"
else
    print_status 1 "Namespace '$NAMESPACE' does not exist"
    exit 1
fi
echo ""

# Check connector pod
echo "2. Checking connector pod..."
CONNECTOR_POD=$(oc get pod -n "$NAMESPACE" -l app=ticket-template -o name 2>/dev/null | head -1)
if [ -n "$CONNECTOR_POD" ]; then
    print_status 0 "Connector pod found: $CONNECTOR_POD"
    
    # Check pod status
    POD_STATUS=$(oc get "$CONNECTOR_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        print_status 0 "Pod is running"
    else
        print_status 1 "Pod status: $POD_STATUS"
    fi
else
    print_status 1 "Connector pod not found"
    echo "   Expected label: app=ticket-template"
fi
echo ""

# Check connector secret
echo "3. Checking connector secret..."
if oc get secret connector -n "$NAMESPACE" &>/dev/null; then
    print_status 0 "Secret 'connector' exists"
    
    # Check secret keys
    echo "   Checking secret keys..."
    for key in id client-id client-secret; do
        if oc get secret connector -n "$NAMESPACE" -o jsonpath="{.data.$key}" &>/dev/null; then
            VALUE=$(oc get secret connector -n "$NAMESPACE" -o jsonpath="{.data.$key}" | base64 -d 2>/dev/null)
            if [ -n "$VALUE" ]; then
                print_status 0 "Key '$key' exists and has value"
            else
                print_status 1 "Key '$key' exists but is empty"
            fi
        else
            print_status 1 "Key '$key' is missing"
        fi
    done
else
    print_status 1 "Secret 'connector' does not exist"
    print_warning "This secret should be created automatically when you configure the integration through the UI"
fi
echo ""

# Check connector bridge
echo "4. Checking connector bridge..."
BRIDGE_POD=$(oc get pod -n "$NAMESPACE" -l app.kubernetes.io/name=connector-bridge -o name 2>/dev/null | head -1)
if [ -n "$BRIDGE_POD" ]; then
    print_status 0 "Connector bridge pod found: $BRIDGE_POD"
    
    # Check bridge status
    BRIDGE_STATUS=$(oc get "$BRIDGE_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$BRIDGE_STATUS" = "Running" ]; then
        print_status 0 "Bridge is running"
    else
        print_status 1 "Bridge status: $BRIDGE_STATUS"
    fi
else
    print_status 1 "Connector bridge pod not found"
fi
echo ""

# Check connector bridge connection info secret
echo "5. Checking connector bridge connection info..."
if oc get secret connector-bridge-connection-info -n "$NAMESPACE" &>/dev/null; then
    print_status 0 "Secret 'connector-bridge-connection-info' exists"
else
    print_status 1 "Secret 'connector-bridge-connection-info' does not exist"
fi
echo ""

# Check connector configuration
echo "6. Checking connector configuration..."
CONNECTOR_CONFIG=$(oc get connectorconfiguration -n "$NAMESPACE" -o name 2>/dev/null | grep -i maximo | head -1)
if [ -n "$CONNECTOR_CONFIG" ]; then
    print_status 0 "Connector configuration found: $CONNECTOR_CONFIG"
    
    # Get config details
    CONFIG_NAME=$(oc get "$CONNECTOR_CONFIG" -n "$NAMESPACE" -o jsonpath='{.metadata.name}')
    CONFIG_STATUS=$(oc get "$CONNECTOR_CONFIG" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    
    if [ "$CONFIG_STATUS" = "True" ]; then
        print_status 0 "Configuration status: Ready"
    else
        print_status 1 "Configuration status: Not Ready"
        print_warning "Check: oc get $CONNECTOR_CONFIG -n $NAMESPACE -o yaml"
    fi
else
    print_status 1 "No Maximo connector configuration found"
    print_warning "You need to create an integration through the AIOps UI"
fi
echo ""

# Check recent connector logs for auth errors
echo "7. Checking connector logs for authentication errors..."
if [ -n "$CONNECTOR_POD" ]; then
    AUTH_ERRORS=$(oc logs "$CONNECTOR_POD" -n "$NAMESPACE" --tail=100 2>/dev/null | grep -c "UNAUTHENTICATED" || true)
    if [ "$AUTH_ERRORS" -gt 0 ]; then
        print_status 1 "Found $AUTH_ERRORS authentication errors in recent logs"
        echo ""
        echo "   Recent authentication errors:"
        oc logs "$CONNECTOR_POD" -n "$NAMESPACE" --tail=100 2>/dev/null | grep "UNAUTHENTICATED" | tail -3 | sed 's/^/   /'
    else
        print_status 0 "No authentication errors in recent logs"
    fi
else
    print_warning "Cannot check logs - connector pod not found"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "SUMMARY AND RECOMMENDATIONS"
echo "=========================================="
echo ""

if [ -z "$CONNECTOR_POD" ]; then
    echo "❌ CRITICAL: Connector pod not found"
    echo "   → Check if the bundle manifest is deployed: oc get bundlemanifest maximo-connector"
    echo "   → Check deployment: oc get deployment ticket-template -n $NAMESPACE"
    echo ""
fi

if ! oc get secret connector -n "$NAMESPACE" &>/dev/null; then
    echo "❌ CRITICAL: Connector secret missing"
    echo "   → This secret is created when you configure the integration through the UI"
    echo "   → Steps to fix:"
    echo "     1. Go to AIOps UI → Integrations"
    echo "     2. Click 'Add Integration'"
    echo "     3. Select 'IBM Maximo'"
    echo "     4. Complete the configuration form"
    echo "     5. Test and save the connection"
    echo ""
fi

if [ "$AUTH_ERRORS" -gt 0 ]; then
    echo "❌ ISSUE: Authentication errors detected"
    echo "   → The connector cannot authenticate with the connector bridge"
    echo "   → Most common fix: Delete and recreate the integration through the UI"
    echo "   → Steps:"
    echo "     1. Delete: oc delete connectorconfiguration <name> -n $NAMESPACE"
    echo "     2. Wait for cleanup: oc get secret connector -n $NAMESPACE (should not exist)"
    echo "     3. Recreate through AIOps UI"
    echo ""
fi

if [ -z "$BRIDGE_POD" ]; then
    echo "⚠️  WARNING: Connector bridge not found"
    echo "   → Check if CP4AIOps is fully installed"
    echo "   → Verify: oc get pods -n $NAMESPACE | grep connector-bridge"
    echo ""
fi

echo "For detailed troubleshooting, see: GRPC-AUTH-TROUBLESHOOTING.md"
echo ""

# Made with Bob
