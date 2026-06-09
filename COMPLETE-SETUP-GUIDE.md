# Complete Maximo Connector Setup Guide

## Your Environment

- **Namespace:** `ibm-aiops`
- **Connector:** Maximo Connector
- **Status:** Schema deployed, needs UI refresh

## Current Situation

✅ ConnectorSchema `maximo-connector` is deployed  
✅ Secrets are being created with UUID names  
✅ Code fixes have been applied  
⏳ UI needs to be restarted to show the integration  

## Immediate Action Required

### Step 1: Restart the UI

Run the verification script:
```bash
chmod +x verify-and-fix-ui.sh
./verify-and-fix-ui.sh ibm-aiops
```

Or manually:
```bash
# Restart UI pods
oc delete pod -n ibm-aiops -l app.kubernetes.io/name=aiops-connections-ui

# Wait for restart (30-60 seconds)
oc get pods -n ibm-aiops -l app.kubernetes.io/name=aiops-connections-ui -w
```

### Step 2: Clear Browser Cache

- **Chrome/Edge:** Ctrl+Shift+Delete → Clear cached images and files
- **Firefox:** Ctrl+Shift+Delete → Cached Web Content  
- **Or:** Use Incognito/Private browsing mode

### Step 3: Wait and Access UI

1. Wait 2-3 minutes for UI to fully restart
2. Refresh your browser
3. Go to: **Integrations → Add Integration**
4. Search for: **Maximo**
5. You should now see: **IBM Maximo**

### Step 4: Create the Integration

When you click on IBM Maximo:

1. **Connection Name:** Enter a unique name (e.g., `maximo-prod`)
2. **Maximo URL:** Your Maximo instance URL
3. **Authentication Type:** Select one:
   - Basic Authentication (username/password)
   - API Key
   - OAuth 2.0
4. **Credentials:** Fields will appear based on auth type selected
5. **Organization ID:** Enter your org (e.g., `EAGLENA`)
6. **Site ID:** Optional
7. **Test Connection:** Click to verify
8. **Save:** Create the integration

### Step 5: Verify Authentication

After creating the integration:

```bash
# Check that a secret was created
oc get secret -n ibm-aiops | grep "^connector-"

# Watch connector logs
oc logs -n ibm-aiops -l app=ticket-template -f
```

**Look for:**
- ✅ `starting configuration consume stream`
- ✅ `CloudEventProducer created`
- ✅ NO `UNAUTHENTICATED` errors

## All Fixes Applied

### Fix 1: Correct ConnectorSchema Deployment
**File:** `bundle-artifacts/prereqs/kustomization.yaml`  
**Change:** Now deploys `connectorschema-maximo.yaml` instead of `connectorschema.yaml`

### Fix 2: Dynamic Secret Name Resolution
**File:** `bundle-artifacts/connector/kustomization.yaml`  
**Change:** Added patch to use `CONNECTOR-INSTANCE-SECRET-NAME` placeholder

### Fix 3: Scripts Updated
All scripts now default to `ibm-aiops` namespace:
- `verify-and-fix-ui.sh`
- `diagnose-grpc-auth.sh`
- `fix-connector-auth.sh`

## Verification Commands

```bash
# Check schema is deployed
oc get connectorschema maximo-connector

# Check schema display name
oc get connectorschema maximo-connector -o jsonpath='{.spec.uiSchema.displayName}'
# Should output: IBM Maximo

# Check bundle manifest status
oc get bundlemanifest maximo-connector

# Check connector pod
oc get pods -n ibm-aiops -l app=ticket-template

# Check UI pods
oc get pods -n ibm-aiops -l app.kubernetes.io/name=aiops-connections-ui

# Check secrets
oc get secret -n ibm-aiops | grep connector
```

## Troubleshooting

### Integration Still Not Showing

1. **Verify schema exists:**
   ```bash
   oc get connectorschema maximo-connector -o yaml | grep displayName
   ```

2. **Check UI logs:**
   ```bash
   oc logs -n ibm-aiops -l app.kubernetes.io/name=aiops-connections-ui --tail=100
   ```

3. **Try different browser:**
   - Use incognito mode
   - Try Chrome, Firefox, or Edge
   - Disable browser extensions

4. **Force UI refresh:**
   ```bash
   # Scale down
   oc scale deployment aiops-connections-ui -n ibm-aiops --replicas=0
   sleep 10
   # Scale up
   oc scale deployment aiops-connections-ui -n ibm-aiops --replicas=1
   ```

### Authentication Errors After Creating Integration

If you still see `UNAUTHENTICATED` errors after creating the integration:

1. **Commit and push the fixes:**
   ```bash
   git add bundle-artifacts/prereqs/kustomization.yaml
   git add bundle-artifacts/connector/kustomization.yaml
   git commit -m "Fix: Correct schema and dynamic secret names"
   git push origin main
   ```

2. **Redeploy bundle:**
   ```bash
   oc delete bundlemanifest maximo-connector
   sleep 10
   oc apply -f bundlemanifest-maximo.yaml
   ```

3. **Restart connector pod:**
   ```bash
   oc delete pod -n ibm-aiops -l app=ticket-template
   ```

### Maximo Connection Test Fails

If authentication works but Maximo connection fails:

- **HTTP 401:** Check Maximo credentials
- **HTTP 403:** Check Maximo user permissions
- **HTTP 302:** Use API Key instead of Basic Auth
- **Timeout:** Check network connectivity and firewall rules

## Success Indicators

You'll know everything is working when:

1. ✅ IBM Maximo appears in integration catalog
2. ✅ Authentication fields appear when you select auth type
3. ✅ Connection test succeeds
4. ✅ Integration is created successfully
5. ✅ Secret `connector-<uuid>` is created
6. ✅ Connector logs show no `UNAUTHENTICATED` errors
7. ✅ Integration status shows "Connected" in UI

## Next Steps After Setup

Once authentication is working:

1. **Configure Field Mappings:** Customize how incidents are mapped
2. **Set Up Policies:** Define when to create/update incidents
3. **Enable Data Collection:** Start polling Maximo for incidents
4. **Train AI Models:** Use collected data for Similar Incidents and Change Risk

## Quick Reference

```bash
# Namespace
NAMESPACE=ibm-aiops

# Restart UI
oc delete pod -n $NAMESPACE -l app.kubernetes.io/name=aiops-connections-ui

# Check schema
oc get connectorschema maximo-connector

# Check connector
oc get pods -n $NAMESPACE -l app=ticket-template

# Watch logs
oc logs -n $NAMESPACE -l app=ticket-template -f

# Check secrets
oc get secret -n $NAMESPACE | grep connector
```

## Documentation Index

- **[CRITICAL-FIX-APPLY-NOW.md](CRITICAL-FIX-APPLY-NOW.md)** - Schema fix details
- **[FINAL-FIX-SECRET-NAME.md](FINAL-FIX-SECRET-NAME.md)** - Secret name fix details
- **[UI-FORM-NOT-SHOWING-FIX.md](UI-FORM-NOT-SHOWING-FIX.md)** - UI troubleshooting
- **[NEXT-STEPS.md](NEXT-STEPS.md)** - Post-setup configuration
- **[README-MAXIMO.md](README-MAXIMO.md)** - Full connector documentation

## Support

If you're still having issues after following this guide:

1. Run diagnostic script: `./diagnose-grpc-auth.sh ibm-aiops`
2. Collect logs and configurations
3. Review the troubleshooting guides
4. Contact IBM Support with collected information

---

**You're almost there! Just restart the UI and you should be able to create the integration.** 🚀