# Maximo Connector Connection Fix

## Problem Summary

The Maximo connector was failing to connect to the Maximo REST API with two sequential issues:

### Issue 1: Missing `/maximo` Prefix (HTTP 404)
**Symptom**: Connection attempts were getting HTTP 404 errors
**Root Cause**: API paths were missing the required `/maximo` prefix
**Example of incorrect URL**: `https://mas.../oslc/os/mxincident`
**Example of correct URL**: `https://mas.../maximo/oslc/os/mxincident`

### Issue 2: HTTP Redirects Not Followed (HTTP 302)
**Symptom**: After fixing the path, connection attempts were getting HTTP 302 redirects
**Root Cause**: The Java HttpClient was not configured to follow redirects
**Solution**: Added `.followRedirects(HttpClient.Redirect.NORMAL)` to HttpClient configuration

## Files Modified

### 1. src/main/java/com/ibm/aiops/connectors/template/MaximoHttpClient.java

#### Change 1: Added Redirect Following (Line 69)
```java
this.httpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(30))
        .sslContext(sslContext)
        .followRedirects(HttpClient.Redirect.NORMAL)  // ADDED THIS LINE
        .build();
```

**Why**: Maximo's REST API returns HTTP 302 redirects for authentication. The HttpClient must be configured to automatically follow these redirects.

#### Change 2: Correct API Paths
All Maximo REST API paths now include the `/maximo` prefix:

- **Connection Test** (Line 305):
  ```java
  String testPath = "/maximo/oslc/os/mxincident?oslc.select=ticketid&oslc.pageSize=1&_format=json&lean=1";
  ```

### 2. src/main/java/com/ibm/aiops/connectors/template/MaximoIncidentActions.java

- **Create Incident** (Line 264): `/maximo/oslc/os/mxincident`
- **Update Incident** (Line 314): `/maximo/oslc/os/mxincident/{id}`
- **Close Incident** (Line 360): `/maximo/oslc/os/mxincident/{id}`

### 3. src/main/java/com/ibm/aiops/connectors/template/MaximoIncidentPoller.java

- **Poll Query** (Line 134): `/maximo/oslc/os/mxincident?...`

## Deployment Steps

1. **Build the image**:
   ```bash
   podman build -f container/Dockerfile -t quay.io/jacobdanielrose/maximo-connector:1.2.2 .
   ```

2. **Push to registry**:
   ```bash
   podman push quay.io/jacobdanielrose/maximo-connector:1.2.2
   podman push quay.io/jacobdanielrose/maximo-connector:latest
   ```

3. **Delete existing pod to force image pull**:
   ```bash
   oc delete pod -n ibm-aiops -l app=ticket-template
   ```

4. **Verify new pod is using correct image**:
   ```bash
   oc get pods -n ibm-aiops | grep ticket-template
   oc describe pod <pod-name> -n ibm-aiops | grep "Image ID"
   ```

5. **Check logs for successful connection**:
   ```bash
   oc logs -n ibm-aiops <pod-name> | grep "GET request"
   ```

## Expected Results

After the fix, you should see:
- ✅ GET requests to URLs with `/maximo` prefix
- ✅ HTTP 200 responses instead of 404 or 302
- ✅ Connector status changes from "Retrying" to "Running"
- ✅ Successful connection test messages in logs

## Verification Commands

```bash
# Check connector status
oc get aiopsedge -n ibm-aiops maximo-connector-<id>

# View recent logs
oc logs -n ibm-aiops <pod-name> --tail=100

# Search for connection test results
oc logs -n ibm-aiops <pod-name> | grep -E "Testing connection|Connection test|GET request"
```

## Technical Notes

### Why `/maximo` is Required
IBM Maximo Application Suite (MAS) uses a context root of `/maximo` for all REST API endpoints. This is part of the standard Maximo OSLC (Open Services for Lifecycle Collaboration) API structure.

### Why Redirect Following is Required
Maximo's authentication mechanism may return HTTP 302 redirects to handle authentication flows. The Java HttpClient, by default, does NOT follow redirects automatically. Setting `.followRedirects(HttpClient.Redirect.NORMAL)` enables automatic redirect following for HTTP 301, 302, 303, 307, and 308 status codes.

## Version History

- **v1.2.2**: Added redirect following to HttpClient
- **v1.2.1**: Fixed API paths to include `/maximo` prefix
- **v1.2.0**: Initial Maximo connector implementation