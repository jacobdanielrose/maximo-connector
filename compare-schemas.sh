#!/bin/bash

# Script to compare Maximo schema with working schemas
# Usage: ./compare-schemas.sh

NAMESPACE="ibm-aiops"

echo "=========================================="
echo "Connector Schema Comparison"
echo "=========================================="
echo ""

echo "All ConnectorSchemas in cluster:"
oc get connectorschema

echo ""
echo "=========================================="
echo ""

# Get a working schema for comparison
echo "Getting a working schema for comparison..."
WORKING_SCHEMA=$(oc get connectorschema -o name | grep -v maximo | head -1)

if [ -n "$WORKING_SCHEMA" ]; then
    SCHEMA_NAME=$(basename "$WORKING_SCHEMA")
    echo "Comparing with: $SCHEMA_NAME"
    echo ""
    
    echo "Maximo schema authType configuration:"
    echo "---"
    oc get connectorschema maximo-connector -o yaml | grep -A 60 "id: authType" | head -60
    echo "---"
    echo ""
    
    echo "Working schema ($SCHEMA_NAME) form configuration:"
    echo "---"
    oc get "$WORKING_SCHEMA" -o yaml | grep -A 60 "type: radio" | head -60
    echo "---"
else
    echo "No other schemas found for comparison"
    echo ""
    echo "Maximo schema full uiSchema:"
    echo "---"
    oc get connectorschema maximo-connector -o yaml | grep -A 200 "uiSchema:"
    echo "---"
fi

echo ""
echo "=========================================="
echo "Checking schema validation"
echo "=========================================="
echo ""

# Check if schema has validation errors
oc describe connectorschema maximo-connector | grep -A 10 "Events:"

echo ""
echo "=========================================="
echo "Maximo schema type and display name:"
echo "=========================================="
echo ""

echo "Type: $(oc get connectorschema maximo-connector -o jsonpath='{.spec.uiSchema.type}')"
echo "Display Name: $(oc get connectorschema maximo-connector -o jsonpath='{.spec.uiSchema.displayName}')"
echo "Has form: $(oc get connectorschema maximo-connector -o yaml | grep -c '\"form\":')"
echo "Has authType: $(oc get connectorschema maximo-connector -o yaml | grep -c 'id: authType')"

echo ""

# Made with Bob
