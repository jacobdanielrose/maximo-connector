# Fix: Authentication Fields Not Showing in UI

## The Problem

You can select the authentication type (Basic/API Key/OAuth) but the input fields for credentials don't appear below it.

## Root Cause

The AIOps UI has cached the old schema or hasn't refreshed to pick up the new `maximo-connector` schema. The UI needs to be restarted to load the updated schema.

## Solution: Restart the Connections UI

### Option 1: Delete the UI Pod (Recommended)

```bash
NAMESPACE=cp4waiops  # adjust if different

# Delete the connections UI pod to force restart
oc delete pod -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui

# Wait for new pod to start (30-60 seconds)
oc get pods -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui -w

# Press Ctrl+C when pod shows "Running"
```

### Option 2: Scale Down and Up

If the above doesn't work:

```bash
# Scale down to 0
oc scale deployment aiops-connections-ui -n $NAMESPACE --replicas=0

# Wait 10 seconds
sleep 10

# Scale back up to 1
oc scale deployment aiops-connections-ui -n $NAMESPACE --replicas=1

# Wait for pod to be ready
oc get pods -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui -w
```

### Option 3: Clear Browser Cache

Sometimes the issue is browser-side caching:

1. **Clear browser cache:**
   - Chrome/Edge: Ctrl+Shift+Delete → Clear cached images and files
   - Firefox: Ctrl+Shift+Delete → Cached Web Content
   - Safari: Cmd+Option+E

2. **Hard refresh the page:**
   - Chrome/Edge/Firefox: Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)
   - Safari: Cmd+Option+R

3. **Try incognito/private mode:**
   - Open a new incognito/private window
   - Log into AIOps
   - Try creating the integration again

## Verification Steps

After restarting the UI:

### 1. Wait for UI to Be Ready

```bash
# Check UI pod status
oc get pods -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui

# Should show "Running" and "1/1" ready
```

### 2. Access the UI Again

1. Log into AIOps UI
2. Go to: **Integrations** → **Add Integration**
3. Search for and select: **IBM Maximo**

### 3. Verify Form Fields Appear

When you select an authentication type, you should now see:

**For Basic Authentication:**
- Username field
- Password field

**For API Key:**
- API Key field

**For OAuth 2.0:**
- OAuth Token URL field
- Client ID field
- Client Secret field

## If Fields Still Don't Appear

### Check Schema is Correct

```bash
# Verify the schema has the form configuration
oc get connectorschema maximo-connector -o yaml | grep -A 50 "authType"

# Should show the radio button and nested form fields
```

### Check for Schema Errors

```bash
# Check if there are any validation errors
oc describe connectorschema maximo-connector

# Look for any error messages in the Events section
```

### Verify UI Logs

```bash
# Check UI logs for errors
oc logs -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui --tail=100

# Look for errors related to schema loading or form rendering
```

### Check Browser Console

1. Open browser developer tools (F12)
2. Go to Console tab
3. Look for JavaScript errors when you:
   - Open the integration form
   - Select an authentication type

Common errors:
- Schema validation errors
- Form rendering errors
- API communication errors

## Alternative: Use a Different Browser

Sometimes browser-specific issues can cause form rendering problems:

1. Try a different browser (Chrome, Firefox, Edge, Safari)
2. Ensure JavaScript is enabled
3. Disable browser extensions that might interfere

## Manual Workaround: Create Configuration via CLI

If the UI still doesn't work, you can create the configuration manually:

```bash
NAMESPACE=cp4waiops

# Create a ConnectorConfiguration YAML file
cat > maximo-connector-config.yaml <<EOF
apiVersion: connectors.aiops.ibm.com/v1beta1
kind: ConnectorConfiguration
metadata:
  name: maximo-prod
  namespace: $NAMESPACE
spec:
  type: maximo-connector
  connection_config:
    display_name: "Maximo Production"
    description: "Maximo production instance"
    url: "https://your-maximo-url.com"
    authType: "basic"
    username: "your-username"
    password: "your-password"
    maximoOrgId: "EAGLENA"
    datasource_type:
      - tickets
    data_flow: true
    collectionMode: "live"
    issueSamplingRate: 5
EOF

# Apply it
oc apply -f maximo-connector-config.yaml

# Check if secret was created
oc get secret connector -n $NAMESPACE
```

**Note:** Replace the values with your actual Maximo configuration.

## Expected Behavior After Fix

Once the UI is restarted and cache is cleared:

1. ✅ Select "Basic Authentication" → Username and Password fields appear
2. ✅ Select "API Key" → API Key field appears
3. ✅ Select "OAuth 2.0" → Token URL, Client ID, and Client Secret fields appear
4. ✅ All fields are editable and accept input
5. ✅ Required fields show validation errors if left empty
6. ✅ Test Connection button works

## Common UI Issues and Fixes

### Issue: Radio buttons don't respond
**Fix:** Hard refresh the page (Ctrl+Shift+R)

### Issue: Fields appear but are disabled
**Fix:** Check if you're editing an existing integration (some fields are read-only on edit)

### Issue: Form is completely blank
**Fix:** 
1. Check browser console for errors
2. Restart UI pod
3. Try different browser

### Issue: "Schema not found" error
**Fix:**
```bash
# Verify schema exists
oc get connectorschema maximo-connector

# If not found, redeploy
oc apply -f bundle-artifacts/prereqs/connectorschema-maximo.yaml
```

## Prevention

To avoid this issue in the future:

1. **Always restart UI after schema changes:**
   ```bash
   oc delete pod -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui
   ```

2. **Wait for schema to be fully loaded:**
   - After deploying bundle manifest, wait 2-3 minutes
   - Verify schema exists before accessing UI

3. **Clear browser cache regularly:**
   - Especially after CP4AIOps updates
   - Use incognito mode for testing

## Still Not Working?

If fields still don't appear after all these steps:

1. **Check CP4AIOps version:**
   ```bash
   oc get csv -n $NAMESPACE | grep aiops
   ```
   Ensure you're on 4.3.0 or later.

2. **Check for known issues:**
   - Review IBM CP4AIOps release notes
   - Check for any UI-related patches

3. **Contact IBM Support** with:
   - ConnectorSchema YAML
   - UI pod logs
   - Browser console errors
   - Screenshots of the issue

## Quick Command Summary

```bash
NAMESPACE=cp4waiops

# Restart UI
oc delete pod -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui

# Check UI status
oc get pods -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui

# Check UI logs
oc logs -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui --tail=100

# Verify schema
oc get connectorschema maximo-connector -o yaml
```

---

**Most likely fix:** Just restart the UI pod and clear your browser cache. The schema is correct, the UI just needs to reload it.