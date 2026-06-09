# Schema Form Fix - Authentication Fields Not Showing

## Problem Identified

The authentication fields weren't showing in the UI because the schema had `formStep: addConnection` on the nested field rows, which caused the UI form renderer to fail silently.

## The Fix

**File:** `bundle-artifacts/prereqs/connectorschema-maximo.yaml`

**Issue:** Each nested field (username, password, apiKey, etc.) had `formStep: addConnection` which shouldn't be there.

**Fixed:** Removed `formStep` from all nested field definitions. The `formStep` should only be on the parent `authType` element.

### Before (Incorrect):
```yaml
- id: username
  element: input
  type: text
  label: "Username"
  apiMapping: connection_config.username
  formStep: addConnection  # ❌ This shouldn't be here
  isRequired: true
```

### After (Correct):
```yaml
- id: username
  element: input
  type: text
  label: "Username"
  apiMapping: connection_config.username
  isRequired: true  # ✅ No formStep on nested fields
```

## How to Apply

### Step 1: Commit and Push the Fix

```bash
git add bundle-artifacts/prereqs/connectorschema-maximo.yaml
git commit -m "Fix: Remove formStep from nested auth fields in schema"
git push origin main
```

### Step 2: Update the Schema in Cluster

```bash
# Apply the fixed schema directly
oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml

# Verify it was updated
oc get connectorschema maximo-connector -o yaml | grep -A 10 "id: username"
```

### Step 3: Restart the UI

```bash
# Restart UI pods to reload the schema
oc delete pod -n ibm-aiops -l app.kubernetes.io/name=aiops-connections-ui

# Wait for restart
oc get pods -n ibm-aiops -l app.kubernetes.io/name=aiops-connections-ui -w
```

### Step 4: Clear Browser Cache

- **Chrome/Edge:** Ctrl+Shift+Delete → Clear cached images and files
- **Firefox:** Ctrl+Shift+Delete → Cached Web Content
- **Or:** Use Incognito/Private mode

### Step 5: Test the Form

1. Wait 2-3 minutes for UI to fully restart
2. Refresh your browser
3. Go to: **Integrations → Add Integration**
4. Select: **IBM Maximo**
5. Select an authentication type
6. **Fields should now appear!**

## Expected Behavior After Fix

When you select:
- **Basic Authentication** → Username and Password fields appear
- **API Key** → API Key field appears
- **OAuth 2.0** → Token URL, Client ID, and Client Secret fields appear

## Why This Happened

The CP4AIOps UI form renderer expects:
- `formStep` only on top-level form elements
- Nested fields (inside `rows`) should NOT have `formStep`
- When nested fields have `formStep`, the renderer fails silently

This is a common mistake when creating connector schemas based on templates.

## Verification

After applying the fix:

```bash
# Check the schema is correct
oc get connectorschema maximo-connector -o yaml | grep -B 2 -A 5 "id: username"

# Should show username field WITHOUT formStep
```

## Complete Fix Summary

Three fixes have been applied to make the connector work:

1. ✅ **Schema deployment** - Fixed kustomization to deploy correct schema
2. ✅ **Secret name resolution** - Fixed deployment to use dynamic secret names
3. ✅ **Form fields** - Removed incorrect formStep from nested fields

## Timeline

- Apply schema fix: 1 minute
- UI restart: 1-2 minutes
- Browser cache clear: 30 seconds
- **Total: ~3-4 minutes**

## Success Indicators

You'll know it's fixed when:
1. ✅ Select authentication type in UI
2. ✅ Fields appear immediately below the radio buttons
3. ✅ Fields are editable and accept input
4. ✅ Required field validation works
5. ✅ Test Connection button is enabled

---

**This fix resolves the UI form rendering issue. The fields will now appear correctly when you select an authentication type.**