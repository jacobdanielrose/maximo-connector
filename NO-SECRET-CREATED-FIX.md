# Fix: Connector Secret Not Being Created

## The Problem

You've created the integration through the UI, but the `connector` secret is not being created. This causes the authentication error because the connector pod cannot find the credentials it needs.

## Root Causes

This happens when:
1. The ConnectorSchema is not properly registered
2. The BundleManifest deployment failed or is incomplete
3. There's a mismatch between the connector type in the schema and the deployment
4. The connector operator/controller is not running or has errors

## Diagnostic Steps

### 1. Check if ConnectorSchema is Registered

```bash
NAMESPACE=cp4waiops  # adjust if needed

# Check if the schema exists
oc get connectorschema maximo-connector

# If it exists, check its details
oc get connectorschema maximo-connector -o yaml
```

**Expected output:**
- Should show `maximo-connector` schema
- Should have `components[0].name: connector` (this is critical!)

### 2. Check BundleManifest Status

```bash
# Check bundle manifest
oc get bundlemanifest maximo-connector

# Check detailed status
oc get bundlemanifest maximo-connector -o yaml
```

**Expected status:** `Configured`

If not configured, check:
```bash
# Check bundle manifest events
oc describe bundlemanifest maximo-connector

# Check for errors in the operator
oc logs -n $NAMESPACE -l app.kubernetes.io/name=connector-operator --tail=100
```

### 3. Check Connector Operator

```bash
# Check if connector operator is running
oc get pods -n $NAMESPACE | grep connector-operator

# Check operator logs
oc logs -n $NAMESPACE -l app.kubernetes.io/name=connector-operator --tail=100
```

### 4. Check ConnectorConfiguration

```bash
# List all connector configurations
oc get connectorconfiguration -n $NAMESPACE

# Check your specific configuration
oc get connectorconfiguration <your-config-name> -n $NAMESPACE -o yaml
```

Look for errors in the status section.

## Solutions

### Solution 1: Redeploy the Bundle Manifest

The schema might not be properly registered:

```bash
# Delete the bundle manifest
oc delete bundlemanifest maximo-connector

# Wait 10 seconds

# Reapply it
oc apply -f bundlemanifest-maximo.yaml

# Wait for it to be configured (may take 1-2 minutes)
oc get bundlemanifest maximo-connector -w
```

Once it shows `Configured`:
```bash
# Verify the schema is registered
oc get connectorschema maximo-connector

# Now recreate your integration through the UI
```

### Solution 2: Check and Fix the ConnectorSchema

The schema might have the wrong component name:

```bash
# Get the current schema
oc get connectorschema maximo-connector -o yaml > /tmp/schema.yaml

# Check the components section
grep -A 5 "components:" /tmp/schema.yaml
```

It should show:
```yaml
components:
  - apiType: AsyncAPI
    name: connector
```

If the `name` is different (e.g., `ticket-template`), that's the problem. The deployment expects `connector` but the schema defines something else.

**Fix:** Update the schema:
```bash
# Edit the schema
oc edit connectorschema maximo-connector

# Change the component name to: connector
# Save and exit
```

Then recreate the integration through the UI.

### Solution 3: Manual Secret Creation (Temporary Workaround)

If the automatic creation still fails, you can manually create the secret as a temporary workaround:

```bash
NAMESPACE=cp4waiops

# Generate random credentials
CLIENT_ID=$(openssl rand -hex 16)
CLIENT_SECRET=$(openssl rand -hex 32)
CONNECTOR_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

# Create the secret
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: connector
  namespace: $NAMESPACE
type: Opaque
stringData:
  id: "$CONNECTOR_ID"
  client-id: "$CLIENT_ID"
  client-secret: "$CLIENT_SECRET"
EOF

# Restart the connector pod
oc delete pod -n $NAMESPACE -l app=ticket-template
```

**WARNING:** This is a workaround. The proper fix is to ensure the schema and bundle manifest are correctly deployed so the secret is created automatically.

### Solution 4: Check Connector Bridge Configuration

The bridge might not be configured to create secrets for this connector type:

```bash
# Check connector bridge configuration
oc get configmap -n $NAMESPACE | grep connector-bridge

# Check bridge logs for errors
oc logs -n $NAMESPACE -l app.kubernetes.io/name=connector-bridge --tail=200 | grep -i error
```

### Solution 5: Verify Namespace and RBAC

The connector operator might not have permissions:

```bash
# Check service account
oc get serviceaccount connector -n $NAMESPACE

# Check role bindings
oc get rolebinding -n $NAMESPACE | grep connector

# Check if there are any admission webhook errors
oc get events -n $NAMESPACE --sort-by='.lastTimestamp' | grep -i error | tail -20
```

## Complete Reset Procedure

If nothing else works, do a complete reset:

```bash
NAMESPACE=cp4waiops

# 1. Delete all connector resources
oc delete connectorconfiguration --all -n $NAMESPACE
oc delete secret connector -n $NAMESPACE 2>/dev/null || true
oc delete pod -n $NAMESPACE -l app=ticket-template

# 2. Delete and redeploy bundle manifest
oc delete bundlemanifest maximo-connector
sleep 10
oc apply -f bundlemanifest-maximo.yaml

# 3. Wait for bundle to be configured
oc get bundlemanifest maximo-connector -w
# Press Ctrl+C when it shows "Configured"

# 4. Verify schema is registered
oc get connectorschema maximo-connector

# 5. Check that the component name is "connector"
oc get connectorschema maximo-connector -o jsonpath='{.spec.components[0].name}'
# Should output: connector

# 6. Restart connector bridge (to pick up new schema)
oc delete pod -n $NAMESPACE -l app.kubernetes.io/name=connector-bridge

# 7. Wait for bridge to restart (30-60 seconds)
oc get pods -n $NAMESPACE | grep connector-bridge

# 8. Now create integration through UI
```

## Verification After Fix

After applying any solution:

### 1. Create Integration Through UI
- Go to AIOps UI → Integrations
- Add Integration → IBM Maximo
- Fill in all details
- Save

### 2. Immediately Check for Secret
```bash
# The secret should be created within 5-10 seconds
oc get secret connector -n $NAMESPACE

# If created, check its contents
oc get secret connector -n $NAMESPACE -o yaml
```

### 3. Watch Connector Logs
```bash
oc logs -n $NAMESPACE -l app=ticket-template -f
```

Should see:
- ✓ `starting configuration consume stream`
- ✓ NO `UNAUTHENTICATED` errors

## Why This Happens

The `connector` secret is created by the CP4AIOps connector framework when:
1. A ConnectorConfiguration is created (via UI)
2. The ConnectorSchema exists and is valid
3. The connector operator is running and has permissions
4. The component name in the schema matches what the deployment expects

If any of these conditions fail, the secret won't be created.

## Prevention

1. Always deploy the BundleManifest BEFORE creating integrations
2. Verify the bundle shows "Configured" status
3. Check that the ConnectorSchema is registered
4. Ensure the connector operator is running
5. Don't manually edit the ConnectorSchema unless necessary

## Still Not Working?

If the secret still isn't being created:

1. **Check CP4AIOps version compatibility:**
   ```bash
   oc get csv -n $NAMESPACE | grep aiops
   ```
   Ensure you're on CP4AIOps 4.3.0 or later.

2. **Check for conflicting connectors:**
   ```bash
   oc get connectorschema | grep -i maximo
   ```
   Delete any duplicates.

3. **Review operator logs in detail:**
   ```bash
   oc logs -n $NAMESPACE -l app.kubernetes.io/name=connector-operator --tail=500
   ```
   Look for errors related to secret creation.

4. **Check admission webhooks:**
   ```bash
   oc get validatingwebhookconfiguration | grep connector
   oc get mutatingwebhookconfiguration | grep connector
   ```

5. **Contact IBM Support** with:
   - Bundle manifest YAML
   - ConnectorSchema YAML
   - Operator logs
   - ConnectorConfiguration YAML
   - Any error messages from events

## Quick Command Summary

```bash
NAMESPACE=cp4waiops

# Check everything
oc get bundlemanifest maximo-connector
oc get connectorschema maximo-connector
oc get connectorconfiguration -n $NAMESPACE
oc get secret connector -n $NAMESPACE
oc get pods -n $NAMESPACE | grep -E "connector|ticket-template"

# Reset everything
oc delete bundlemanifest maximo-connector
oc delete connectorconfiguration --all -n $NAMESPACE
oc delete secret connector -n $NAMESPACE
oc apply -f bundlemanifest-maximo.yaml

# Watch for secret creation after creating integration
watch -n 2 "oc get secret connector -n $NAMESPACE"