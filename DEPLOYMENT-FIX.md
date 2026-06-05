# Fixing InvalidImageName Error - Maximo Connector

## Problem
The deployment fails with `InvalidImageName` because the image `ticket-template:unreleased-main-latest` doesn't exist in any registry.

## Solution Options

You have **3 options** to fix this:

---

## Option 1: Build and Push to Your Own Registry (Recommended)

### Step 1: Set Up Your Registry

```bash
# Set your container registry details
export REGISTRY="your-registry.com"  # e.g., quay.io/yourorg, docker.io/youruser
export REGISTRY_USERNAME="your-username"
export REGISTRY_PASSWORD="your-password"
export TAG="1.0.0"  # or "latest"
```

### Step 2: Build the Container Image

```bash
# Login to your registry
docker login $REGISTRY -u "$REGISTRY_USERNAME" -p "$REGISTRY_PASSWORD"

# Build the image
make docker-build REGISTRY=$REGISTRY TAG=$TAG
```

This will create an image named:
```
your-registry.com/cp/aiopsedge/cp4waiops-connector-ticket-template:1.0.0
```

### Step 3: Push to Registry

```bash
make docker-push REGISTRY=$REGISTRY TAG=$TAG
```

### Step 4: Update Deployment to Use Your Image

Update [`bundle-artifacts/connector/deployment.yaml`](bundle-artifacts/connector/deployment.yaml:39):

```yaml
# Change line 39 and 69 from:
image: ticket-template:unreleased-main-latest

# To:
image: your-registry.com/cp/aiopsedge/cp4waiops-connector-ticket-template:1.0.0
```

### Step 5: Create Image Pull Secret (if using private registry)

```bash
oc create secret docker-registry maximo-pull-secret \
  --docker-server=$REGISTRY \
  --docker-username=$REGISTRY_USERNAME \
  --docker-password=$REGISTRY_PASSWORD \
  --docker-email=your-email@example.com
```

Update deployment to use this secret (line 20):
```yaml
imagePullSecrets:
  - name: maximo-pull-secret  # Change from ibm-aiops-pull-secret
```

---

## Option 2: Use IBM Entitled Registry (If You Have Access)

### Step 1: Get IBM Entitlement Key

1. Go to https://myibm.ibm.com/products-services/containerlibrary
2. Copy your entitlement key

### Step 2: Create Pull Secret

```bash
export IBM_ENTITLEMENT_KEY="your-entitlement-key"

oc create secret docker-registry ibm-entitlement-key \
  --docker-server=cp.icr.io \
  --docker-username=cp \
  --docker-password=$IBM_ENTITLEMENT_KEY
```

### Step 3: Build and Push to IBM Registry

```bash
export REGISTRY="cp.icr.io/cp/aiopsedge"
export TAG="1.0.0"

# Build
make docker-build REGISTRY=$REGISTRY TAG=$TAG

# Push
docker push cp.icr.io/cp/aiopsedge/cp4waiops-connector-ticket-template:1.0.0
```

### Step 4: Update Deployment

```yaml
image: cp.icr.io/cp/aiopsedge/cp4waiops-connector-ticket-template:1.0.0
imagePullSecrets:
  - name: ibm-entitlement-key
```

---

## Option 3: Use OpenShift Internal Registry (Simplest for Testing)

### Step 1: Enable Internal Registry

```bash
# Check if internal registry is available
oc get route -n openshift-image-registry

# If not available, expose it
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --patch '{"spec":{"defaultRoute":true}}' --type=merge
```

### Step 2: Get Registry URL

```bash
export REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
echo $REGISTRY
```

### Step 3: Login to Internal Registry

```bash
# Get token
export TOKEN=$(oc whoami -t)

# Login
docker login -u $(oc whoami) -p $TOKEN $REGISTRY
```

### Step 4: Build and Push

```bash
export PROJECT_NAME=$(oc project -q)
export IMAGE_NAME="maximo-connector"
export TAG="1.0.0"

# Build
docker build -f container/Dockerfile -t $REGISTRY/$PROJECT_NAME/$IMAGE_NAME:$TAG .

# Push
docker push $REGISTRY/$PROJECT_NAME/$IMAGE_NAME:$TAG
```

### Step 5: Update Deployment

```yaml
# Update lines 39 and 69 in deployment.yaml
image: image-registry.openshift-image-registry.svc:5000/your-namespace/maximo-connector:1.0.0

# Remove imagePullSecrets (not needed for internal registry)
# imagePullSecrets:
#   - name: ibm-aiops-pull-secret
```

---

## Quick Fix Script

Save this as `build-and-deploy.sh`:

```bash
#!/bin/bash
set -e

# Configuration
REGISTRY="${REGISTRY:-image-registry.openshift-image-registry.svc:5000}"
PROJECT=$(oc project -q)
IMAGE_NAME="maximo-connector"
TAG="${TAG:-1.0.0}"
FULL_IMAGE="$REGISTRY/$PROJECT/$IMAGE_NAME:$TAG"

echo "Building image: $FULL_IMAGE"

# Build the image
docker build -f container/Dockerfile -t $FULL_IMAGE .

# Push to registry
echo "Pushing image to registry..."
docker push $FULL_IMAGE

# Update deployment.yaml
echo "Updating deployment.yaml..."
sed -i.bak "s|image: ticket-template:unreleased-main-latest|image: $FULL_IMAGE|g" \
  bundle-artifacts/connector/deployment.yaml

echo "✅ Image built and deployment updated!"
echo "Next steps:"
echo "1. Apply the bundle manifest: oc apply -f bundlemanifest-maximo.yaml"
echo "2. Check pod status: oc get pods -l app=ticket-template"
```

Run it:
```bash
chmod +x build-and-deploy.sh
./build-and-deploy.sh
```

---

## Verification Steps

After updating the deployment:

### 1. Check Image Exists

```bash
# For external registry
docker pull your-registry.com/cp/aiopsedge/cp4waiops-connector-ticket-template:1.0.0

# For internal registry
oc get imagestream maximo-connector
```

### 2. Apply Updated Deployment

```bash
# If using bundle manifest
oc apply -f bundlemanifest-maximo.yaml

# Or apply deployment directly
oc apply -f bundle-artifacts/connector/deployment.yaml
```

### 3. Check Pod Status

```bash
# Watch pod creation
oc get pods -l app=ticket-template -w

# Check for image pull errors
oc describe pod -l app=ticket-template | grep -A 10 "Events:"
```

### 4. View Logs

```bash
# If pod is running
oc logs -l app=ticket-template --tail=50

# If pod is failing
oc logs -l app=ticket-template --previous
```

---

## Common Issues

### Issue: "unauthorized: authentication required"

**Solution:** Create or update image pull secret

```bash
oc create secret docker-registry my-pull-secret \
  --docker-server=your-registry.com \
  --docker-username=your-user \
  --docker-password=your-password
```

### Issue: "manifest unknown"

**Solution:** Image doesn't exist. Verify:
```bash
docker images | grep maximo-connector
```

### Issue: "ImagePullBackOff"

**Solution:** Check image name and pull secret:
```bash
oc get events --sort-by='.lastTimestamp' | grep -i pull
oc describe pod -l app=ticket-template
```

---

## Recommended Approach for Production

1. **Use a proper container registry** (Quay.io, Docker Hub, or IBM Cloud Container Registry)
2. **Tag images with version numbers** (not "latest")
3. **Use image pull secrets** for private registries
4. **Implement CI/CD pipeline** to automate builds
5. **Scan images for vulnerabilities** before deployment

---

## Example: Complete Workflow with Quay.io

```bash
# 1. Set variables
export REGISTRY="quay.io/yourorg"
export IMAGE_NAME="maximo-connector"
export TAG="1.0.0"

# 2. Login
docker login quay.io

# 3. Build
docker build -f container/Dockerfile -t $REGISTRY/$IMAGE_NAME:$TAG .

# 4. Push
docker push $REGISTRY/$IMAGE_NAME:$TAG

# 5. Update deployment
sed -i "s|ticket-template:unreleased-main-latest|$REGISTRY/$IMAGE_NAME:$TAG|g" \
  bundle-artifacts/connector/deployment.yaml

# 6. Create pull secret
oc create secret docker-registry quay-pull-secret \
  --docker-server=quay.io \
  --docker-username=youruser \
  --docker-password=yourpassword

# 7. Update deployment to use secret
# Edit bundle-artifacts/connector/deployment.yaml line 20:
# imagePullSecrets:
#   - name: quay-pull-secret

# 8. Deploy
oc apply -f bundlemanifest-maximo.yaml

# 9. Verify
oc get pods -l app=ticket-template
oc logs -l app=ticket-template --tail=50
```

---

## Need Help?

If you're still having issues:

1. **Check pod events:**
   ```bash
   oc describe pod -l app=ticket-template
   ```

2. **Check image pull logs:**
   ```bash
   oc get events --sort-by='.lastTimestamp' | grep -i image
   ```

3. **Verify registry access:**
   ```bash
   docker pull your-registry.com/your-image:tag
   ```

4. **Check secrets:**
   ```bash
   oc get secrets | grep pull
   oc describe secret your-pull-secret