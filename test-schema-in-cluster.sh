#!/bin/bash

# Script to test if the schema in cluster has the complete form configuration
# Usage: ./test-schema-in-cluster.sh

NAMESPACE="ibm-aiops"

echo "=========================================="
echo "Testing Maximo Schema in Cluster"
echo "=========================================="
echo ""

echo "1. Checking if schema exists..."
if ! oc get connectorschema maximo-connector &>/dev/null; then
    echo "❌ Schema does not exist!"
    echo "Run: oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml"
    exit 1
fi
echo "✓ Schema exists"
echo ""

echo "2. Checking schema metadata..."
echo "Created: $(oc get connectorschema maximo-connector -o jsonpath='{.metadata.creationTimestamp}')"
echo "Resource Version: $(oc get connectorschema maximo-connector -o jsonpath='{.metadata.resourceVersion}')"
echo ""

echo "3. Checking for form configuration..."
HAS_FORM=$(oc get connectorschema maximo-connector -o yaml | grep -c "form:" || echo "0")
echo "Found 'form:' keyword: $HAS_FORM times"
echo ""

echo "4. Checking for authType field..."
HAS_AUTHTYPE=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: authType" || echo "0")
echo "Found 'id: authType': $HAS_AUTHTYPE times"
echo ""

echo "5. Checking for nested auth fields..."
HAS_USERNAME=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: username" || echo "0")
HAS_PASSWORD=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: password" || echo "0")
HAS_APIKEY=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: apiKey" || echo "0")
HAS_OAUTH_URL=$(oc get connectorschema maximo-connector -o yaml | grep -c "id: oauthTokenUrl" || echo "0")

echo "Found 'id: username': $HAS_USERNAME"
echo "Found 'id: password': $HAS_PASSWORD"
echo "Found 'id: apiKey': $HAS_APIKEY"
echo "Found 'id: oauthTokenUrl': $HAS_OAUTH_URL"
echo ""

echo "=========================================="
echo "DIAGNOSIS"
echo "=========================================="
echo ""

if [ "$HAS_USERNAME" -eq "0" ] && [ "$HAS_PASSWORD" -eq "0" ] && [ "$HAS_APIKEY" -eq "0" ]; then
    echo "❌ PROBLEM: Schema is missing the nested authentication fields!"
    echo ""
    echo "The schema in the cluster does NOT have the form configuration."
    echo "This is why the UI doesn't show the fields."
    echo ""
    echo "SOLUTION:"
    echo "1. Apply the schema directly:"
    echo "   oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml"
    echo ""
    echo "2. Verify it worked:"
    echo "   ./test-schema-in-cluster.sh"
    echo ""
    echo "3. If it still fails, the schema file might have YAML formatting issues."
    echo "   Check for proper indentation in the 'form:' section."
    echo ""
elif [ "$HAS_USERNAME" -gt "0" ]; then
    echo "✓ Schema HAS the nested authentication fields!"
    echo ""
    echo "The schema is correct in the cluster."
    echo "If UI still doesn't show fields, the issue is:"
    echo ""
    echo "1. UI hasn't reloaded the schema:"
    echo "   - Restart UI pods"
    echo "   - Clear browser cache completely"
    echo "   - Wait 2-3 minutes"
    echo ""
    echo "2. Browser caching issue:"
    echo "   - Use incognito/private mode"
    echo "   - Try different browser"
    echo ""
    echo "3. UI version incompatibility:"
    echo "   - Check CP4AIOps version"
    echo "   - Schema format might need adjustment for your version"
    echo ""
fi

echo "=========================================="
echo "Full authType section from cluster:"
echo "=========================================="
echo ""
oc get connectorschema maximo-connector -o yaml | grep -A 100 "id: authType" | head -100

echo ""
echo "=========================================="
echo ""

# Made with Bob
