# CRITICAL FIX - Apply Immediately

## The Problem Found

The BundleManifest was deploying the **wrong ConnectorSchema**. It was deploying `connectorschema.yaml` (named `ticket-template`) instead of `connectorschema-maximo.yaml` (named `maximo-connector`).

This is why:
- ❌ No `maximo-connector` schema was registered
- ❌ No `connector` secret was created
- ❌ Authentication failed with `UNAUTHENTICATED` errors

## The Fix Applied

Updated [`bundle-artifacts/prereqs/kustomization.yaml`](bundle-artifacts/prereqs/kustomization.yaml) to reference the correct schema file:

```yaml
resources:
  - connectorschema-maximo.yaml  # ✓ Changed from connectorschema.yaml
  - microedgeconfiguration.yaml
```

## How to Apply the Fix

### Step 1: Commit and Push the Fix

```bash
# Add the fixed file
git add bundle-artifacts/prereqs/kustomization.yaml

# Commit
git commit -m "Fix: Use correct Maximo connector schema in kustomization"

# Push to GitHub
git push origin main
```

### Step 2: Redeploy the BundleManifest

```bash
# Set your namespace
NAMESPACE=cp4waiops  # adjust if different

# Delete the old bundle manifest
oc delete bundlemanifest maximo-connector

# Wait 10 seconds for cleanup
sleep 10

# Reapply the bundle manifest (it will pull the updated code from GitHub)
oc apply -f bundlemanifest-maximo.yaml

# Wait for it to be configured (1-2 minutes)
oc get bundlemanifest maximo-connector -w
# Press Ctrl+C when status shows "Configured"
```

### Step 3: Verify the Schema is Now Deployed

```bash
# Check if the schema exists
oc get connectorschema maximo-connector

# Should show:
# NAME                AGE
# maximo-connector    <time>

# Verify it has the correct component name
oc get connectorschema maximo-connector -o jsonpath='{.spec.components[0].name}'
# Should output: connector
```

### Step 4: Wait for Connector Pod to Start

```bash
# Watch for the pod to be created
oc get pods -n $NAMESPACE -l app=ticket-template -w

# Wait until it shows "Running" status
# Press Ctrl+C when running
```

### Step 5: Create Integration Through UI

Now that the schema is properly deployed:

1. **Open AIOps UI**
   - Navigate to: Integrations → Add Integration

2. **Select IBM Maximo**
   - You should now see "IBM Maximo" in the integration catalog
   - Click to start configuration

3. **Fill in Configuration**
   - **Connection Name**: e.g., `maximo-prod`
   - **Maximo URL**: Your Maximo instance URL
   - **Authentication Type**: Choose Basic/API Key/OAuth
   - **Credentials**: Enter your Maximo credentials
   - **Organization ID**: e.g., `EAGLENA`
   - **Site ID**: Optional

4. **Test and Save**
   - Click "Test Connection"
   - Wait for success
   - Click "Save"

### Step 6: Verify Secret is Created

```bash
# The secret should be created within 5-10 seconds
oc get secret connector -n $NAMESPACE

# If created successfully, check its contents
oc get secret connector -n $NAMESPACE -o yaml

# Should have keys: id, client-id, client-secret
```

### Step 7: Verify Authentication Works

```bash
# Watch connector logs
oc logs -n $NAMESPACE -l app=ticket-template -f

# Look for:
# ✓ "starting configuration consume stream: channel=grpc-connector-configuration-updates-channel"
# ✓ "CloudEventProducer created"
# ✓ NO "UNAUTHENTICATED" errors
```

## Expected Results

After applying this fix:

1. ✅ `maximo-connector` ConnectorSchema will be registered
2. ✅ `connector` secret will be automatically created when you create the integration
3. ✅ Connector will authenticate successfully with the bridge
4. ✅ No more `UNAUTHENTICATED` errors
5. ✅ Connector can then connect to Maximo

## Timeline

- **Commit & Push**: 1 minute
- **Bundle Redeployment**: 2-3 minutes
- **Pod Restart**: 1-2 minutes
- **Integration Creation**: 2-3 minutes
- **Total**: ~10 minutes

## Verification Checklist

After completing all steps, verify:

- [ ] `oc get connectorschema maximo-connector` shows the schema
- [ ] `oc get bundlemanifest maximo-connector` shows "Configured"
- [ ] `oc get pods -n $NAMESPACE -l app=ticket-template` shows "Running"
- [ ] Integration created through UI
- [ ] `oc get secret connector -n $NAMESPACE` shows the secret
- [ ] Connector logs show no `UNAUTHENTICATED` errors
- [ ] Connector logs show successful configuration stream

## Why This Happened

The repository had two schema files:
- `connectorschema.yaml` - Old template schema (name: `ticket-template`)
- `connectorschema-maximo.yaml` - Correct Maximo schema (name: `maximo-connector`)

The kustomization was pointing to the wrong one, so the Maximo schema was never deployed.

## Prevention

Going forward:
1. Always verify the schema is deployed: `oc get connectorschema maximo-connector`
2. Check the bundle manifest status: `oc get bundlemanifest maximo-connector`
3. Don't create integrations until the schema is confirmed deployed

---

**This fix resolves the root cause of all the authentication errors you were seeing.**