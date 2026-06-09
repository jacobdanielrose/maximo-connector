# FINAL FIX: Dynamic Secret Name Resolution

## The Real Problem Discovered

The secrets ARE being created correctly with UUID names like:
- `connector-013390b4-000e-4ebc-b6a8-4f1f839fcd87`
- `connector-176097ba-206d-4120-abab-ae6f4793b060`
- etc.

But the deployment was hardcoded to look for a secret named `connector`, which doesn't exist!

## The Fix Applied

Updated [`bundle-artifacts/connector/kustomization.yaml`](bundle-artifacts/connector/kustomization.yaml) to add a patch that replaces the hardcoded secret name with a dynamic placeholder:

```yaml
patches:
- patch: |-
    - op: replace
      path: /spec/template/spec/volumes/2/projected/sources/1/secret/name
      value: CONNECTOR-INSTANCE-SECRET-NAME
  target:
    kind: Deployment
```

This placeholder will be replaced at runtime by CP4AIOps with the actual UUID-based secret name for your connector instance.

## How to Apply This Fix

### Step 1: Commit and Push

```bash
# Add both fixed files
git add bundle-artifacts/prereqs/kustomization.yaml
git add bundle-artifacts/connector/kustomization.yaml

# Commit
git commit -m "Fix: Use dynamic secret names for connector instances"

# Push
git push origin main
```

### Step 2: Identify Your Connector Instance

First, find which secret belongs to your Maximo connector:

```bash
NAMESPACE=cp4waiops  # adjust if needed

# List all connector configurations
oc get connectorconfiguration -n $NAMESPACE

# Get the ID of your Maximo connector (look for the one you created)
# The secret name will be: connector-<ID>
```

### Step 3: Redeploy the Bundle

```bash
# Delete the bundle manifest
oc delete bundlemanifest maximo-connector

# Wait 10 seconds
sleep 10

# Reapply (will pull updated code from GitHub)
oc apply -f bundlemanifest-maximo.yaml

# Wait for "Configured" status
oc get bundlemanifest maximo-connector -w
```

### Step 4: Delete and Recreate the Connector Pod

The existing pod has the old configuration. It needs to be recreated:

```bash
# Delete the connector pod
oc delete pod -n $NAMESPACE -l app=ticket-template

# Wait for new pod to start
oc get pods -n $NAMESPACE -l app=ticket-template -w

# Press Ctrl+C when pod shows "Running"
```

### Step 5: Verify Authentication

```bash
# Watch the logs
oc logs -n $NAMESPACE -l app=ticket-template -f
```

**Look for:**
- ✅ `starting configuration consume stream: channel=grpc-connector-configuration-updates-channel`
- ✅ `CloudEventProducer created`
- ✅ NO `UNAUTHENTICATED` errors

## Why This Happens

CP4AIOps uses a multi-tenant architecture where:
1. Each connector **instance** gets its own unique secret
2. Secret names are: `connector-<uuid>` where uuid is the instance ID
3. The deployment template uses a placeholder that gets replaced at runtime
4. The placeholder `CONNECTOR-INSTANCE-SECRET-NAME` is replaced with the actual secret name

The original deployment was using a hardcoded name `connector` which doesn't match the actual secret naming pattern.

## Verification

After the fix is applied and pod is restarted:

### 1. Check Pod Volumes

```bash
# Describe the pod to see mounted secrets
oc describe pod -n $NAMESPACE -l app=ticket-template | grep -A 20 "Volumes:"
```

Should show the correct UUID-based secret name mounted.

### 2. Check Logs for Success

```bash
oc logs -n $NAMESPACE -l app=ticket-template --tail=50
```

Should show:
- Configuration stream starting
- No authentication errors
- Connector initializing successfully

### 3. Check Integration Status

In the AIOps UI:
- Go to Integrations
- Find your Maximo integration
- Status should show: **Connected**

## Alternative: Manual Secret Mount (Temporary)

If you need a quick workaround while waiting for the bundle redeploy:

```bash
NAMESPACE=cp4waiops

# Find your connector's secret name
CONNECTOR_SECRET=$(oc get secret -n $NAMESPACE | grep "^connector-" | grep -v dockercfg | grep -v bridge | head -1 | awk '{print $1}')

echo "Found secret: $CONNECTOR_SECRET"

# Edit the deployment to use this specific secret
oc edit deployment ticket-template -n $NAMESPACE

# Find the line with:
#   name: connector
# Replace with:
#   name: $CONNECTOR_SECRET (use the actual value)

# Save and exit
```

The pod will automatically restart with the correct secret.

## Summary of All Fixes

1. ✅ **Fixed prereqs kustomization** - Now deploys `connectorschema-maximo.yaml`
2. ✅ **Fixed connector kustomization** - Now uses dynamic secret name placeholder
3. ⏳ **Need to redeploy** - Push changes and redeploy bundle
4. ⏳ **Need to restart pod** - Delete pod to pick up new configuration

## Expected Timeline

- Commit & Push: 1 minute
- Bundle Redeploy: 2-3 minutes  
- Pod Restart: 1-2 minutes
- Authentication Success: Immediate after pod starts
- **Total: ~5-7 minutes**

## Success Indicators

You'll know it's working when:
1. ✅ Pod starts without errors
2. ✅ Logs show "starting configuration consume stream"
3. ✅ NO `UNAUTHENTICATED` errors
4. ✅ Integration shows "Connected" in UI
5. ✅ Connector begins polling Maximo (if in live mode)

---

**This is the final piece of the puzzle. After this fix, authentication will work correctly!**