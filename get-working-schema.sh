#!/bin/bash

# Get a working schema to use as a template
echo "Getting ServiceNow schema as reference..."
oc get connectorschema servicenow -o yaml > /tmp/servicenow-schema.yaml

echo "Extracting the form structure with radio buttons..."
echo ""
echo "=========================================="
echo "ServiceNow Radio Button Form Structure:"
echo "=========================================="
grep -B 5 -A 100 'type: radio' /tmp/servicenow-schema.yaml | head -120

echo ""
echo "=========================================="
echo "Full ServiceNow form section:"
echo "=========================================="
grep -A 300 'form:' /tmp/servicenow-schema.yaml | head -300

echo ""
echo "Schema saved to: /tmp/servicenow-schema.yaml"
echo "Review this file to see the exact structure that works in your environment"

# Made with Bob
