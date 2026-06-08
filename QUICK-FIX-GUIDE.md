# Quick Fix Guide for gRPC Authentication Error

## The Error You're Seeing

```
io.grpc.StatusRuntimeException: UNAUTHENTICATED: unable to authenticate client, 
invalid client_id or client_secret in encoded credentials
```

## What This Means

**This is NOT a Maximo authentication problem.** Your connector cannot authenticate with the CP4AIOps platform itself. The connector never even tries to connect to Maximo because it fails to authenticate with the internal connector bridge first.

## Quick Fix (Most Common Solution)

### Step 1: Delete the Existing Integration

```bash
# Replace <namespace> with your CP4AIOps namespace (usually cp4waiops)
NAMESPACE=ibm-aiops

# Find your connector configuration
oc get connectorconfiguration -n $NAMESPACE

# Delete it (replace <config-name> with the actual name)
oc delete connectorconfiguration <config-name> -n $NAMESPACE

# Verify the connector secret is gone
oc get secret connector -n $NAMESPACE
# Should return: Error from server (NotFound): secrets "connector" not found
```

### Step 2: Recreate Through the UI

1. **Open AIOps UI**
   - Navigate to: Integrations → Add Integration

2. **Select IBM Maximo**
   - Find "IBM Maximo" in the integration catalog
   - Click to start configuration

3. **Fill in Connection Details**
   - **Connection Name**: Give it a unique name (e.g., `maximo-prod`)
   - **Description**: Optional description
   - **Maximo URL**: Your Maximo base URL (e.g., `https://maximo.example.com`)
   
4. **Choose Authentication Method**
   
   **Option A: Basic Authentication** (Most Common)
   - Select "Basic Authentication"
   - Username: Your Maximo username
   - Password: Your Maximo password
   
   **Option B: API Key** (For MAS)
   - Select "API Key"
   - API Key: Your Maximo API key
   
   **Option C: OAuth 2.0** (If configured)
   - Select "OAuth 2.0"
   - Token URL: OAuth endpoint
   - Client ID: OAuth client ID
   - Client Secret: OAuth client secret

5. **Maximo Configuration**
   - **Organization ID**: Usually `EAGLENA` (check with your Maximo admin)
   - **Site ID**: Optional, leave blank if not needed

6. **Test Connection**
   - Click "Test Connection"
   - Wait for success message
   - If it fails, verify your Maximo credentials and URL

7. **Save**
   - Click "Save" or "Create"
   - Wait for the integration to be created

### Step 3: Verify It's Working

```bash
# Watch the connector logs
oc logs -n $NAMESPACE -l app=ticket-template -f

# You should see:
# - "starting configuration consume stream"
# - NO "UNAUTHENTICATED" errors
# - "CloudEventProducer created"
# - Configuration updates being received
```

## Run the Diagnostic Tool

Before attempting the fix, run the diagnostic script to identify the exact issue:

```bash
./diagnose-grpc-auth.sh <namespace>
```

This will check:
- ✓ Connector pod status
- ✓ Connector secret existence and contents
- ✓ Connector bridge status
- ✓ Recent authentication errors
- ✓ Configuration status

## Why This Happens

1. **Integration created before bundle deployment**: The UI created a secret for a different connector type
2. **Stale credentials**: The connector bridge rotated its credentials
3. **Manual secret creation**: Secrets were created manually instead of through the UI
4. **Namespace issues**: Connector and bridge are in different namespaces

## Alternative Fixes

### If Deleting/Recreating Doesn't Work

1. **Check connector bridge health:**
   ```bash
   oc get pods -n $NAMESPACE | grep connector-bridge
   oc logs -n $NAMESPACE -l app.kubernetes.io/name=connector-bridge --tail=100
   ```

2. **Restart connector bridge:**
   ```bash
   oc delete pod -n $NAMESPACE -l app.kubernetes.io/name=connector-bridge
   ```

3. **Verify bundle manifest:**
   ```bash
   oc get bundlemanifest maximo-connector
   # Should show: Configured
   ```

4. **Check for multiple instances:**
   ```bash
   oc get connectorconfiguration -n $NAMESPACE
   # Delete any duplicates
   ```

## Still Not Working?

See the detailed troubleshooting guide: [`GRPC-AUTH-TROUBLESHOOTING.md`](./GRPC-AUTH-TROUBLESHOOTING.md)

## Important Notes

- ⚠️ **Always use the UI to create integrations** - don't manually create secrets
- ⚠️ **Deploy the bundle manifest first** before creating integrations
- ⚠️ **Each integration needs a unique name** to avoid conflicts
- ⚠️ **The connector and bridge must be in the same namespace**

## Success Indicators

After the fix, you should see in the logs:

```
[INFO] starting configuration consume stream: channel=grpc-connector-configuration-updates-channel
[INFO] CloudEventProducer created
[INFO] starting manager
[INFO] event cycle starting
```

**NO** `UNAUTHENTICATED` errors should appear.

## Next Steps After Fix

Once authentication is working:

1. **Test Maximo Connection**: The connector will now attempt to connect to Maximo
2. **Monitor for Maximo Auth Issues**: Watch for HTTP 401/403 errors (different from gRPC auth)
3. **Verify Data Flow**: Check that incidents are being polled/created
4. **Configure Field Mappings**: Customize how incidents are mapped

---

**Remember**: This error is about CP4AIOps internal authentication, not Maximo authentication. Fix the gRPC auth first, then address any Maximo connection issues separately.