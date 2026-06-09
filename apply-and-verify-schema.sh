#!/bin/bash

# Script to apply schema and immediately verify the form section persists
# Usage: ./apply-and-verify-schema.sh

set -e

echo "=========================================="
echo "Apply and Verify Schema"
echo "=========================================="
echo ""

echo "Step 1: Applying schema..."
if oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml; then
    echo "✓ Schema applied"
else
    echo "✗ Failed to apply schema"
    exit 1
fi

echo ""
echo "Step 2: Waiting 2 seconds for API server to process..."
sleep 2

echo ""
echo "Step 3: Checking if form section exists..."
FORM_COUNT=$(oc get connectorschema maximo-connector -o yaml | grep -c "form:" || echo "0")
echo "Found 'form:' keyword: $FORM_COUNT times"

echo ""
echo "Step 4: Checking authType structure..."
echo "---"
oc get connectorschema maximo-connector -o yaml | grep -B 5 -A 50 "id: authType" | head -60
echo "---"

echo ""
if oc get connectorschema maximo-connector -o yaml | grep -A 5 "id: authType" | grep -q "form:"; then
    echo "✓ SUCCESS: The 'form:' section IS present under authType!"
    echo ""
    echo "The schema is correct. If UI still doesn't show fields:"
    echo "1. This might be a UI version compatibility issue"
    echo "2. Try creating the integration via CLI instead"
    echo "3. Check CP4AIOps version - schema format may have changed"
else
    echo "✗ PROBLEM: The 'form:' section is NOT present under authType!"
    echo ""
    echo "This means Kubernetes is stripping out the form section when applying."
    echo "Possible causes:"
    echo "1. ConnectorSchema CRD doesn't support nested 'form' under radio buttons"
    echo "2. Validation webhook is rejecting it"
    echo "3. Schema version incompatibility"
    echo ""
    echo "SOLUTION: Use the CLI method to create integrations"
    echo "Run: ./create-integration-manually.sh"
fi

echo ""

# Made with Bob
