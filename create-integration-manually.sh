#!/bin/bash

# Script to create Maximo connector integration manually via CLI
# Use this if the UI form fields are not showing
# Usage: ./create-integration-manually.sh

set -e

NAMESPACE="ibm-aiops"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Manual Maximo Integration Creation"
echo "=========================================="
echo ""
echo "This script will create a Maximo connector integration"
echo "by directly creating a ConnectorConfiguration resource."
echo ""

# Prompt for configuration
read -p "Integration Name (e.g., maximo-prod): " INTEGRATION_NAME
read -p "Maximo URL (e.g., https://maximo.example.com): " MAXIMO_URL

echo ""
echo "Select Authentication Type:"
echo "1) Basic Authentication (username/password)"
echo "2) API Key"
echo "3) OAuth 2.0"
read -p "Enter choice (1-3): " AUTH_CHOICE

case $AUTH_CHOICE in
    1)
        AUTH_TYPE="basic"
        read -p "Username: " USERNAME
        read -sp "Password: " PASSWORD
        echo ""
        AUTH_CONFIG="username: \"$USERNAME\"
    password: \"$PASSWORD\""
        ;;
    2)
        AUTH_TYPE="apikey"
        read -sp "API Key: " API_KEY
        echo ""
        AUTH_CONFIG="apiKey: \"$API_KEY\""
        ;;
    3)
        AUTH_TYPE="oauth"
        read -p "OAuth Token URL: " OAUTH_URL
        read -p "Client ID: " CLIENT_ID
        read -sp "Client Secret: " CLIENT_SECRET
        echo ""
        AUTH_CONFIG="oauthTokenUrl: \"$OAUTH_URL\"
    oauthClientId: \"$CLIENT_ID\"
    oauthClientSecret: \"$CLIENT_SECRET\""
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

read -p "Organization ID (default: EAGLENA): " ORG_ID
ORG_ID=${ORG_ID:-EAGLENA}

read -p "Site ID (optional, press Enter to skip): " SITE_ID

read -p "Description (optional): " DESCRIPTION

echo ""
echo -e "${BLUE}Creating ConnectorConfiguration...${NC}"

# Create the configuration YAML
cat > /tmp/maximo-connector-config.yaml <<EOF
apiVersion: connectors.aiops.ibm.com/v1beta1
kind: ConnectorConfiguration
metadata:
  name: $INTEGRATION_NAME
  namespace: $NAMESPACE
spec:
  type: maximo-connector
  connection_config:
    display_name: "$INTEGRATION_NAME"
    description: "$DESCRIPTION"
    url: "$MAXIMO_URL"
    authType: "$AUTH_TYPE"
    $AUTH_CONFIG
    maximoOrgId: "$ORG_ID"
EOF

# Add site ID if provided
if [ -n "$SITE_ID" ]; then
    echo "    maximoSiteId: \"$SITE_ID\"" >> /tmp/maximo-connector-config.yaml
fi

# Add remaining config
cat >> /tmp/maximo-connector-config.yaml <<EOF
    datasource_type:
      - tickets
    data_flow: true
    collectionMode: "live"
    issueSamplingRate: 5
EOF

echo ""
echo "Configuration to be created:"
echo "---"
cat /tmp/maximo-connector-config.yaml
echo "---"
echo ""

read -p "Create this configuration? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    rm /tmp/maximo-connector-config.yaml
    exit 0
fi

# Apply the configuration
if oc apply -f /tmp/maximo-connector-config.yaml; then
    echo -e "${GREEN}✓${NC} ConnectorConfiguration created successfully"
else
    echo -e "${RED}✗${NC} Failed to create ConnectorConfiguration"
    rm /tmp/maximo-connector-config.yaml
    exit 1
fi

rm /tmp/maximo-connector-config.yaml

echo ""
echo -e "${BLUE}Waiting for secret to be created...${NC}"
sleep 5

# Check if secret was created
CONNECTOR_SECRET=$(oc get secret -n $NAMESPACE | grep "^connector-" | grep -v dockercfg | grep -v bridge | tail -1 | awk '{print $1}')

if [ -n "$CONNECTOR_SECRET" ]; then
    echo -e "${GREEN}✓${NC} Secret created: $CONNECTOR_SECRET"
else
    echo -e "${YELLOW}⚠${NC} Secret not found yet. It may take a few more seconds."
    echo "   Check with: oc get secret -n $NAMESPACE | grep connector"
fi

echo ""
echo -e "${BLUE}Checking connector pod...${NC}"

CONNECTOR_POD=$(oc get pod -n $NAMESPACE -l app=ticket-template -o name 2>/dev/null | head -1)
if [ -n "$CONNECTOR_POD" ]; then
    echo -e "${GREEN}✓${NC} Connector pod found: $CONNECTOR_POD"
    echo ""
    echo "Watching logs for authentication..."
    echo "Press Ctrl+C to stop"
    echo ""
    sleep 2
    oc logs -n $NAMESPACE -l app=ticket-template -f --tail=20
else
    echo -e "${RED}✗${NC} Connector pod not found"
    echo "   Check with: oc get pods -n $NAMESPACE -l app=ticket-template"
fi

echo ""
echo "=========================================="
echo "Integration created!"
echo "=========================================="
echo ""
echo "To check status:"
echo "  oc get connectorconfiguration $INTEGRATION_NAME -n $NAMESPACE"
echo ""
echo "To view in UI:"
echo "  Go to AIOps UI → Integrations"
echo "  You should see: $INTEGRATION_NAME"
echo ""
echo "To check logs:"
echo "  oc logs -n $NAMESPACE -l app=ticket-template -f"
echo ""

# Made with Bob
