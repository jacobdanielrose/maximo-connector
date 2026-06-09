# Final Deployment Steps - Complete Fix

## Summary of All Issues Found and Fixed

1. ✅ **Wrong schema file deployed** - Fixed kustomization to use `connectorschema-maximo.yaml`
2. ✅ **Hardcoded secret name** - Fixed deployment to use dynamic placeholder
3. ✅ **Incorrect formStep placement** - Removed from nested fields
4. ⏳ **Schema not applied to cluster** - Needs to be applied with complete form configuration

## Complete Deployment Procedure

### Step 1: Commit All Fixes

```bash
# Add all fixed files
git add bundle-artifacts/prereqs/kustomization.yaml
git add bundle-artifacts/connector/kustomization.yaml
git add bundle-artifacts/prereqs/connectorschema-maximo.yaml

# Commit
git commit -m "Fix: Complete Maximo connector schema and deployment configuration

- Use correct schema file (connectorschema-maximo.yaml)
- Use dynamic secret name placeholder
- Remove formStep from nested auth fields
- Ensure complete form configuration"

# Push
git push origin main
```

### Step 2: Apply Schema Directly

**IMPORTANT:** Apply the schema directly first, before redeploying the bundle:

```bash
# Apply the complete schema with all form fields
oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml

# Verify it was applied correctly
oc get connectorschema maximo-connector -o yaml | grep -A 50 "id: authType"
```

**Expected output should show:**
```yaml
- id: authType
  element: input
  type: radio
  label: "Authentication Type"
  items:
    - "Basic Authentication"
    - "API Key"
    - "OAuth 2.0"
  itemKeys: ["basic", "apikey", "oauth"]
  apiMapping: connection_config.authType
  formStep: addConnection
  form:                           # ← This section MUST be present
    - id: basic
      rows:
        - id: username
          element: input
          type: text
          label: "Username"
          ...
```

### Step 3: Redeploy Bundle Manifest

```bash
# Delete the bundle manifest
oc delete bundlemanifest maximo-connector

# Wait for cleanup
sleep 10

# Reapply
oc apply -f bundlemanifest-maximo.yaml

# Wait for "Configured" status
oc get bundlemanifest maximo-connector -w
```

### Step 4: Verify Schema Persists

After bundle deployment, verify the schema still has the form fields:

```bash
# Check if form fields are still there
oc get connectorschema maximo-connector -o yaml | grep -c "id: username"
# Should return a number > 0

# If it returns 0, the bundle overwrote the schema
# In that case, reapply the schema again:
oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml
```

### Step 5: Restart UI Pods

```bash
# Find UI pods
oc get pods -n ibm-aiops | grep -iE "(ui|connection|console|portal)"

# Restart them (replace with actual pod names)
oc delete pod <ui-pod-name> -n ibm-aiops

# Or use the script
chmod +x find-and-restart-ui.sh
./find-and-restart-ui.sh
```

### Step 6: Clear Browser and Test

1. **Clear browser cache completely:**
   - Chrome/Edge: Ctrl+Shift+Delete → Select "All time" → Clear cached images and files
   - Firefox: Ctrl+Shift+Delete → Select "Everything" → Cached Web Content
   - **Or use Incognito/Private mode**

2. **Wait 2-3 minutes** for UI to fully restart

3. **Test the form:**
   - Go to AIOps UI
   - Navigate to: Integrations → Add Integration
   - Select: IBM Maximo
   - Select authentication type (Basic/API Key/OAuth)
   - **Fields should now appear!**

## Verification Checklist

Before testing in UI, verify:

- [ ] Schema file locally has complete form configuration
  ```bash
  grep -c "id: username" bundle-artifacts/prereqs/connectorschema-maximo.yaml
  # Should return > 0
  ```

- [ ] Schema in cluster has complete form configuration
  ```bash
  oc get connectorschema maximo-connector -o yaml | grep -c "id: username"
  # Should return > 0
  ```

- [ ] Bundle manifest is "Configured"
  ```bash
  oc get bundlemanifest maximo-connector
  # Should show: Configured
  ```

- [ ] Connector pod is running
  ```bash
  oc get pods -n ibm-aiops -l app=ticket-template
  # Should show: Running
  ```

- [ ] UI pods have been restarted
  ```bash
  oc get pods -n ibm-aiops | grep -i ui
  # Check AGE column - should be recent
  ```

## If Fields Still Don't Appear

### Option A: Manual Schema Verification

```bash
# Get the exact schema from cluster
oc get connectorschema maximo-connector -o yaml > /tmp/maximo-schema-cluster.yaml

# Compare with local file
diff bundle-artifacts/prereqs/connectorschema-maximo.yaml /tmp/maximo-schema-cluster.yaml

# If they differ, the cluster version is wrong
```

### Option B: Force Schema Update

```bash
# Delete the schema
oc delete connectorschema maximo-connector

# Wait 5 seconds
sleep 5

# Reapply
oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml

# Verify
oc get connectorschema maximo-connector -o yaml | grep -A 100 "id: authType"
```

### Option C: Check for Schema Validation Errors

```bash
# Check for errors
oc describe connectorschema maximo-connector

# Look for validation errors in Events section
```

## Alternative: Use CLI to Create Integration

If UI still doesn't work after all steps, use the CLI method:

```bash
chmod +x create-integration-manually.sh
./create-integration-manually.sh
```

This bypasses the UI completely and creates the integration directly.

## Success Indicators

You'll know it's working when:

1. ✅ Schema in cluster has `form:` section with nested fields
2. ✅ UI shows IBM Maximo in integration catalog
3. ✅ Selecting auth type shows input fields below
4. ✅ Fields are editable and accept input
5. ✅ Test Connection button works
6. ✅ Integration can be saved
7. ✅ Secret `connector-<uuid>` is created
8. ✅ Connector logs show no `UNAUTHENTICATED` errors

## Quick Command Reference

```bash
# Apply schema
oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml

# Verify schema
oc get connectorschema maximo-connector -o yaml | grep -A 50 "id: authType"

# Check for form fields
oc get connectorschema maximo-connector -o yaml | grep -c "id: username"

# Restart UI
oc get pods -n ibm-aiops | grep -i ui
oc delete pod <ui-pod-name> -n ibm-aiops

# Check connector
oc get pods -n ibm-aiops -l app=ticket-template
oc logs -n ibm-aiops -l app=ticket-template -f
```

## Files Modified

1. `bundle-artifacts/prereqs/kustomization.yaml` - Use correct schema file
2. `bundle-artifacts/connector/kustomization.yaml` - Dynamic secret name
3. `bundle-artifacts/prereqs/connectorschema-maximo.yaml` - Removed formStep from nested fields

## Next Steps After Successful Deployment

Once the integration is created and working:

1. Configure field mappings (optional)
2. Set up policies for incident creation
3. Enable data collection (live or historical mode)
4. Train AI models with collected data

---

**The key is ensuring the schema with complete form configuration is applied to the cluster and persists after bundle deployment.**