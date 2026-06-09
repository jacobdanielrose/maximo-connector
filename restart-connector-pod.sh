#!/bin/bash

echo "=========================================="
echo "Restarting Maximo Connector Pod"
echo "=========================================="
echo ""

# Delete the existing pod to force pull of new image
echo "Deleting current pod to pull new image..."
oc delete pod -n ibm-aiops -l app=ticket-template

echo ""
echo "Waiting for new pod to start..."
sleep 10

# Check pod status
echo ""
echo "Pod status:"
oc get pods -n ibm-aiops -l app=ticket-template

echo ""
echo "Waiting for pod to be ready..."
oc wait --for=condition=ready pod -l app=ticket-template -n ibm-aiops --timeout=120s

echo ""
echo "=========================================="
echo "Checking Connection Test"
echo "=========================================="
echo ""

# Wait a bit for the connector to initialize
sleep 15

# Check logs for connection test
echo "Recent logs:"
oc logs -n ibm-aiops -l app=ticket-template --tail=50 | grep -A 5 -B 5 "Testing connection\|Connection test\|Maximo connection"

echo ""
echo "=========================================="
echo "Checking Connector Status"
echo "=========================================="
echo ""

# Check connector configuration status
oc get connectorconfiguration maximo -n ibm-aiops -o jsonpath='{.status.components.connector.phase}' && echo ""

echo ""
echo "Full status:"
oc get connectorconfiguration maximo -n ibm-aiops -o yaml | grep -A 10 "status:"

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "If you see 'Connection test successful' above, the fix worked!"
echo "The connector status should change from 'Retrying' to 'Running'"
echo ""
echo "To monitor logs in real-time:"
echo "  oc logs -n ibm-aiops -l app=ticket-template -f"
echo ""

# Made with Bob
