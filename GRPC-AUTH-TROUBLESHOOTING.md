# gRPC Authentication Troubleshooting Guide

## Problem

The connector is failing to authenticate with the CP4AIOps Connector Bridge with the error:

```
io.grpc.StatusRuntimeException: UNAUTHENTICATED: unable to authenticate client, invalid client_id or client_secret in encoded credentials
```

## Root Cause

This is **NOT** a Maximo authentication issue. The connector cannot authenticate with the CP4AIOps platform itself. The gRPC client credentials are either:
1. Missing
2. Invalid
3. Not properly synchronized between the connector and the bridge

## Solution Steps

### Step 1: Verify the Connector Secret Exists

Check if the `connector` secret exists in your namespace:

```bash
oc get secret connector -n <your-namespace>
```

If it doesn't exist, the connector was not properly configured through the UI.

### Step 2: Check Secret Contents

Verify the secret has the required keys:

```bash
oc get secret connector -n <your-namespace> -o yaml
```

Expected keys:
- `id`: Connector instance ID
- `client-id`: gRPC client ID for authentication
- `client-secret`: gRPC client secret for authentication

### Step 3: Delete and Recreate the Integration

The most reliable fix is to delete and recreate the integration through the UI:

1. **Delete the existing integration:**
   ```bash
   # Get the connector configuration name
   oc get connectorconfiguration -n <your-namespace>
   
   # Delete it
   oc delete connectorconfiguration <connector-name> -n <your-namespace>
   ```

2. **Wait for cleanup:**
   ```bash
   # Verify the connector secret is deleted
   oc get secret connector -n <your-namespace>
   ```

3. **Recreate through UI:**
   - Go to AIOps UI → Integrations
   - Click "Add Integration"
   - Select "IBM Maximo"
   - Fill in all configuration details:
     - Connection name
     - Maximo URL
     - Authentication type and credentials
     - Organization ID
     - Site ID (if needed)
   - Test the connection
   - Save

### Step 4: Verify Connector Bridge is Running

Check that the connector bridge is healthy:

```bash
# Check connector bridge pods
oc get pods -n <your-namespace> | grep connector-bridge

# Check connector bridge logs
oc logs -n <your-namespace> -l app.kubernetes.io/name=connector-bridge --tail=100
```

### Step 5: Check for Secret Synchronization Issues

Sometimes the secret exists but isn't properly mounted:

```bash
# Check if the connector pod has the secret mounted
oc describe pod -n <your-namespace> -l app=ticket-template | grep -A 10 "Mounts:"

# Restart the connector pod to force remount
oc delete pod -n <your-namespace> -l app=ticket-template
```

### Step 6: Verify Network Connectivity

Ensure the connector can reach the bridge:

```bash
# Get connector bridge service
oc get svc -n <your-namespace> | grep connector-bridge

# Check from connector pod
oc exec -n <your-namespace> -it $(oc get pod -n <your-namespace> -l app=ticket-template -o name | head -1) -- curl -k https://connector-bridge:443
```

## Common Causes

### 1. Integration Created Before Bundle Deployment

If you created the integration in the UI before deploying the bundle manifest, the secret may reference the wrong connector type.

**Fix:** Delete the integration and recreate it after the bundle is fully deployed.

### 2. Multiple Connector Instances

If you have multiple instances of the same connector type, secrets may conflict.

**Fix:** Use unique names for each integration instance.

### 3. Namespace Mismatch

The connector and bridge must be in the same namespace.

**Fix:** Verify both are in the correct namespace:
```bash
oc get pods -n <your-namespace> | grep -E "ticket-template|connector-bridge"
```

### 4. Secret Rotation

If CP4AIOps rotated the bridge credentials, existing connectors need to be recreated.

**Fix:** Delete and recreate the integration through the UI.

## Verification

After fixing, verify the connector authenticates successfully:

```bash
# Watch connector logs
oc logs -n <your-namespace> -l app=ticket-template -f

# Look for successful authentication messages:
# "starting configuration consume stream: channel=grpc-connector-configuration-updates-channel"
# Should NOT be followed by "UNAUTHENTICATED" errors
```

Successful authentication will show:
- Configuration stream starts
- No UNAUTHENTICATED errors
- Connector begins polling or processing events

## Prevention

1. **Always deploy the bundle manifest first** before creating integrations in the UI
2. **Use the UI to create integrations** - don't manually create secrets
3. **Keep connector and bridge versions aligned** with your CP4AIOps version
4. **Monitor connector logs** during initial setup to catch authentication issues early

## Still Having Issues?

If the problem persists after following these steps:

1. Check CP4AIOps platform health:
   ```bash
   oc get pods -n <your-namespace> | grep -E "connector-bridge|aiops"
   ```

2. Review connector bridge logs for additional context:
   ```bash
   oc logs -n <your-namespace> -l app.kubernetes.io/name=connector-bridge --tail=200
   ```

3. Verify the connector schema is properly registered:
   ```bash
   oc get connectorschema maximo-connector -o yaml
   ```

4. Check for any admission webhook errors:
   ```bash
   oc get events -n <your-namespace> --sort-by='.lastTimestamp' | tail -20
   ```

## Related Documentation

- [CP4AIOps Connector Framework](https://www.ibm.com/docs/en/cloud-paks/cp-waiops/4.3.0?topic=integrations-connector-framework)
- [Troubleshooting Integrations](https://www.ibm.com/docs/en/cloud-paks/cp-waiops/4.3.0?topic=integrations-troubleshooting)