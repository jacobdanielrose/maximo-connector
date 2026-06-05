#!/bin/bash
# Simple script to build and deploy Maximo connector

set -e

echo "🚀 Building and Deploying Maximo Connector"
echo "=========================================="

# Get current OpenShift project
PROJECT=$(oc project -q)
echo "📦 Project: $PROJECT"

# Set image details
IMAGE_NAME="maximo-connector"
TAG="1.0.0"

# Check if we can use internal registry, otherwise fall back to public registry
echo ""
echo "🔍 Checking OpenShift internal registry..."
INTERNAL_REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
USE_INTERNAL_REGISTRY=false
REGISTRY_HOST=""

if [ -n "$INTERNAL_REGISTRY" ]; then
    echo "✅ Internal registry found: $INTERNAL_REGISTRY"
    FULL_IMAGE="$INTERNAL_REGISTRY/$PROJECT/$IMAGE_NAME:$TAG"
    DEPLOY_IMAGE="image-registry.openshift-image-registry.svc:5000/$PROJECT/$IMAGE_NAME:$TAG"
    USE_INTERNAL_REGISTRY=true
    REGISTRY_HOST="$INTERNAL_REGISTRY"

    # Login to internal registry
    echo ""
    echo "🔐 Logging into internal registry..."
    TOKEN=$(oc whoami -t)
    podman login -u $(oc whoami) -p $TOKEN $INTERNAL_REGISTRY
else
    echo "⚠️  Internal registry not available, falling back to public registry"

    if [ -z "$REGISTRY" ] || [ -z "$REGISTRY_USER" ] || [ -z "$REGISTRY_PASSWORD" ]; then
        echo ""
        echo "To use a public registry, set these environment variables:"
        echo "   export REGISTRY=quay.io"
        echo "   export REGISTRY_NAMESPACE=yourorg"
        echo "   export REGISTRY_REPOSITORY=yourorg/$IMAGE_NAME   # optional, overrides REGISTRY_NAMESPACE"
        echo "   export REGISTRY_USER=youruser"
        echo "   export REGISTRY_PASSWORD=yourpassword"
        echo ""
        exit 1
    fi

    REGISTRY_NAMESPACE="${REGISTRY_NAMESPACE:-$REGISTRY_USER}"
    REGISTRY_REPOSITORY="${REGISTRY_REPOSITORY:-$REGISTRY_NAMESPACE/$IMAGE_NAME}"
    REGISTRY_HOST=$(echo "$REGISTRY" | sed 's|^https\?://||' | cut -d/ -f1)
    FULL_IMAGE="$REGISTRY_HOST/$REGISTRY_REPOSITORY:$TAG"
    DEPLOY_IMAGE="$FULL_IMAGE"

    # Login to public registry
    echo ""
    echo "🔐 Logging into public registry..."
    echo "$REGISTRY_PASSWORD" | podman login -u "$REGISTRY_USER" --password-stdin "$REGISTRY_HOST"
fi

# Build the image
echo ""
echo "🔨 Building container image..."
echo "   Image: $FULL_IMAGE"
podman build -f container/Dockerfile -t $FULL_IMAGE .

# Push to registry
echo ""
echo "📤 Pushing image to registry..."
if [ "$USE_INTERNAL_REGISTRY" = true ]; then
    podman push --remove-signatures "$FULL_IMAGE"
else
    TMP_ARCHIVE="/tmp/${IMAGE_NAME}-${TAG}.tar"
    TMP_PUSH_IMAGE="localhost/${IMAGE_NAME}:${TAG}"
    echo "📦 Re-tagging image for public registry push..."
    podman tag "$FULL_IMAGE" "$TMP_PUSH_IMAGE"
    echo "📦 Saving image archive for public registry push..."
    podman save --format docker-archive -o "$TMP_ARCHIVE" "$TMP_PUSH_IMAGE"
    echo "📤 Uploading archive to public registry..."
    podman push --remove-signatures "$TMP_ARCHIVE" "docker://$FULL_IMAGE"
    rm -f "$TMP_ARCHIVE"
    podman rmi "$TMP_PUSH_IMAGE" >/dev/null 2>&1 || true
fi

# Update deployment.yaml
echo ""
echo "📝 Updating deployment configuration..."
# Backup original
cp bundle-artifacts/connector/deployment.yaml bundle-artifacts/connector/deployment.yaml.backup

# Update image references
sed -i.tmp "s|image: ticket-template:unreleased-main-latest|image: $DEPLOY_IMAGE|g" \
    bundle-artifacts/connector/deployment.yaml

if [ "$USE_INTERNAL_REGISTRY" = true ]; then
    # Remove imagePullSecrets requirement for internal registry
    sed -i.tmp '/imagePullSecrets:/,/- name: ibm-aiops-pull-secret/d' \
        bundle-artifacts/connector/deployment.yaml
fi

rm bundle-artifacts/connector/deployment.yaml.tmp

echo "✅ Deployment updated"

# Apply the bundle manifest
echo ""
echo "🚢 Deploying to OpenShift..."
oc apply -f bundlemanifest-maximo.yaml

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Check status with:"
echo "   oc get pods -l app=ticket-template"
echo ""
echo "📋 View logs with:"
echo "   oc logs -l app=ticket-template --tail=50 -f"
echo ""
echo "🔄 If you need to rebuild:"
echo "   ./build-and-deploy.sh"

# Made with Bob
