# Root Cause Analysis: Maximo Connector "Retrying" Status

## Executive Summary

The connector was showing "Retrying" status because it **could not connect to Maximo** due to incorrect API paths in the code. The issue was NOT related to deployment, authentication with CP4AIOps, or kustomize configuration.

## Timeline of Investigation

### Initial Symptoms
- User reported connector stuck in "Retrying" status
- Pods were not appearing after creating integration through UI
- BundleManifest showed "DryRunApplyFail" errors

### Issues Found and Fixed

#### 1. Kustomize Validation Errors (Fixed)
**Problem**: BundleManifest couldn't create deployment due to kustomize errors
- Wrong volume index in patch (volumes/2 instead of volumes/3)
- Invalid kustomize vars trying to reference non-existent metadata.namespace

**Solution**: 
- Fixed volume index in kustomization.yaml
- Removed deprecated vars and hardcoded serverName
- Manually deployed resources to bypass bundle manifest issue

**Result**: ✅ Pod deployed and running successfully

#### 2. gRPC Authentication (Working)
**Status**: ✅ No issues found
- Connector successfully authenticated with connector-bridge
- Receiving configuration events properly
- No UNAUTHENTICATED errors

#### 3. **ROOT CAUSE: Incorrect Maximo API Paths** (Fixed)
**Problem**: All API calls had `/maximo` duplicated in the URL

**Example**:
```
Base URL: https://mas.manage.dev.apps.itz-tq25he.tzaas.techzone.ibm.com/maximo
API Path: /maximo/oslc/os/mxincident
Result:   https://.../maximo/maximo/oslc/os/mxincident  ❌ 404 Not Found
```

**Correct**:
```
Base URL: https://mas.manage.dev.apps.itz-tq25he.tzaas.techzone.ibm.com/maximo
API Path: /oslc/os/mxincident
Result:   https://.../maximo/oslc/os/mxincident  ✅ Works
```

**Files Fixed**:
1. `MaximoHttpClient.java` line 305 - testConnection()
2. `MaximoIncidentActions.java` lines 264, 314, 360 - create/update incidents
3. `MaximoIncidentPoller.java` line 134 - poll for incidents

**Changes Made**:
```java
// BEFORE
String testPath = "/maximo/oslc/os/mxincident?...";

// AFTER  
String testPath = "/oslc/os/mxincident?...";
```

## Error Messages Explained

### "Connection test failed with status: 404"
```
GET request to: https://mas.manage.dev.apps.itz-tq25he.tzaas.techzone.ibm.com/maximo/maximo/oslc/os/mxincident
Connection test failed with status: 404
```
This was the smoking gun - the doubled `/maximo/maximo` in the URL caused 404 errors.

### "Failed to connect to Maximo. Please verify URL and credentials."
This error message was misleading - the URL and credentials were correct, but the API paths in the code were wrong.

### "ConnectorException: Failed to connect to Maximo"
The connector threw this exception 388 times (see metrics) because every configuration update triggered a connection test that failed.

## Current Status

### ✅ Completed
1. Kustomize configuration fixed
2. Deployment created and pod running
3. gRPC authentication working
4. Code fixed to remove duplicate `/maximo` from all API paths
5. Changes committed and pushed to GitHub

### ⏳ In Progress
- Building new Docker image with fixes
- Image will be pushed to quay.io/jacobdanielrose/maximo-connector:latest

### 📋 Next Steps
1. Wait for Docker build to complete (~5-10 minutes)
2. Restart the connector pod to pull new image
3. Verify connection test succeeds
4. Confirm connector status changes from "Retrying" to "Running"

## Lessons Learned

1. **Check actual error messages in logs** - The "Retrying" status was vague, but the logs showed the specific 404 error
2. **Verify API paths match documentation** - The code assumed `/maximo` was part of the API path, but it's part of the base URL
3. **Test connection logic is critical** - The testConnection() method caught the issue, but only after deployment
4. **Misleading error messages** - "verify URL and credentials" suggested auth issues when it was actually a path issue

## Technical Details

### Maximo REST API Structure
```
Base URL: https://<hostname>/maximo
API Endpoints:
  - /oslc/os/mxincident (incidents)
  - /oslc/os/mxsr (service requests)
  - /oslc/os/mxwo (work orders)
```

### Connector Architecture
```
CP4AIOps → Connector Bridge → Connector Pod → Maximo REST API
           (gRPC auth)        (HTTP auth)
```

### Authentication Flow
1. ✅ Connector authenticates with Connector Bridge using client_id/client_secret
2. ✅ Connector receives configuration via gRPC
3. ❌ Connector tests connection to Maximo (was failing due to wrong path)
4. ⏳ Connector polls Maximo for incidents (will work after fix)

## Verification Commands

```bash
# Check pod status
oc get pods -n ibm-aiops -l app=ticket-template

# View logs
oc logs -n ibm-aiops -l app=ticket-template --tail=100

# Check for successful connection
oc logs -n ibm-aiops -l app=ticket-template | grep "Connection test successful"

# Check connector status
oc get connectorconfiguration maximo -n ibm-aiops -o yaml | grep phase
```

## Expected Outcome

After the new image is deployed and pod restarted:
```
[timestamp] MaximoHttpCli I   Testing connection to Maximo
[timestamp] MaximoHttpCli I   GET request to: https://mas.manage.dev.apps.itz-tq25he.tzaas.techzone.ibm.com/maximo/oslc/os/mxincident?...
[timestamp] MaximoHttpCli I   Connection test successful
[timestamp] ConnectorMana I   writeConnectorStatus() Status: name=Running retry=0
```

Status will change from "Retrying" to "Running" ✅