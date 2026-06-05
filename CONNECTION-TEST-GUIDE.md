# Connection Test Feature - Maximo Connector

## Overview

The Maximo connector includes a **"Test Connection"** button in the integration wizard that validates your Maximo credentials and connectivity before saving the configuration.

## Where to Find It

When creating or editing a Maximo integration in the AIOps UI:

1. Navigate to **Integrations** → **Add Integration**
2. Search for "**IBM Maximo**"
3. Fill in the connection details (URL, credentials, etc.)
4. Look for the **"Test Connection"** button at the bottom of the form
5. Click it to verify your settings

![Connection Test Button Location](images/connection-test-location.png)

## What It Tests

The connection test performs the following checks:

### 1. **Network Connectivity**
- Verifies the Maximo URL is reachable
- Checks for network/firewall issues
- Validates SSL/TLS certificates

### 2. **Authentication**
- Tests your credentials (username/password, API key, or OAuth)
- For OAuth: Obtains and validates access token
- Verifies user has necessary permissions

### 3. **API Access**
- Makes a minimal query to Maximo OSLC API
- Queries: `/maximo/oslc/os/mxincident?oslc.select=ticketid&oslc.pageSize=1`
- Confirms API is accessible and responding

### 4. **Organization/Site Access**
- If Organization ID is specified, verifies access to that org
- Validates user has permissions for the specified organization

## How It Works

### UI Schema Configuration

The test button is defined in [`connectorschema-maximo.yaml`](bundle-artifacts/prereqs/connectorschema-maximo.yaml:280):

```yaml
- id: connection_test
  element: input
  type: test
  label: "{{connector.common.form.connection_test.label}}"
  helperText: "{{connector.common.form.connection_test.helperText}}"
  formStep: addConnection
```

### Backend Implementation

The test is executed in [`TicketConnector.java`](src/main/java/com/ibm/aiops/connectors/template/TicketConnector.java:104) during the `onConfigure()` method:

```java
@Override
public ActionConnectorSettings onConfigure(ConnectorConfigurationHelper config) {
    // ... configuration setup ...
    
    // Test connection to Maximo
    MaximoHttpClient maximoClient = new MaximoHttpClient(newConfiguration);
    boolean connectionSuccess = maximoClient.testConnection().get();
    
    if (!connectionSuccess) {
        throw new ConnectorException("Failed to connect to Maximo");
    }
    
    // ... continue with configuration ...
}
```

The actual test logic is in [`MaximoHttpClient.java`](src/main/java/com/ibm/aiops/connectors/template/MaximoHttpClient.java:223):

```java
public CompletableFuture<Boolean> testConnection() {
    String testPath = "/maximo/oslc/os/mxincident?oslc.select=ticketid&oslc.pageSize=1";
    
    return get(testPath)
        .thenApply(response -> {
            boolean success = response.statusCode() >= 200 && response.statusCode() < 300;
            if (success) {
                logger.log(Level.INFO, "Connection test successful");
            } else {
                logger.log(Level.WARNING, "Connection test failed with status: " + 
                    response.statusCode());
            }
            return success;
        });
}
```

## Test Results

### ✅ Success

When the test succeeds, you'll see:
- **Green checkmark** ✓ next to the test button
- Message: "Connection test successful"
- You can proceed to save the integration

**What this means:**
- Maximo is reachable
- Credentials are valid
- API is accessible
- User has necessary permissions

### ❌ Failure

When the test fails, you'll see:
- **Red X** ✗ next to the test button
- Error message explaining the issue
- Cannot save the integration until fixed

**Common error messages:**

| Error Message | Cause | Solution |
|---------------|-------|----------|
| "Failed to connect to Maximo" | Network/URL issue | Verify Maximo URL is correct and accessible |
| "Authentication failed" | Invalid credentials | Check username/password or API key |
| "Connection timeout" | Network/firewall | Check firewall rules, VPN connection |
| "SSL certificate error" | Certificate issue | Verify SSL certificate is valid |
| "Unauthorized" | Insufficient permissions | User needs access to incident API |
| "Organization not found" | Invalid org ID | Verify Organization ID is correct |

## Troubleshooting

### Test Button Not Appearing

**Cause:** UI hasn't loaded the schema properly

**Solution:**
```bash
# Force UI refresh
oc delete pod -l app.kubernetes.io/name=aiops-connections-ui

# Wait for pod to restart
oc get pods -l app.kubernetes.io/name=aiops-connections-ui
```

### Test Always Fails

**Check 1: Verify URL**
```bash
# Test from your machine
curl -v https://your-maximo-instance.com/maximo/oslc/os/mxincident

# Test from OpenShift cluster
oc run curl-test --image=curlimages/curl -it --rm -- \
  curl -v https://your-maximo-instance.com/maximo/oslc/os/mxincident
```

**Check 2: Verify Credentials**
```bash
# Test authentication manually
curl -u username:password \
  https://your-maximo-instance.com/maximo/oslc/os/mxincident?oslc.pageSize=1
```

**Check 3: Check Connector Logs**
```bash
# View connector logs during test
oc logs -l app=ticket-template --tail=50 -f

# Look for lines like:
# "Testing connection to Maximo..."
# "Connection test successful" or "Connection test failed"
```

### Test Succeeds But Integration Fails Later

This can happen if:
1. **Permissions are limited**: Test uses minimal query, but full sync needs more permissions
2. **Network is intermittent**: Test passed but connection dropped later
3. **Token expired**: For OAuth, token may expire after initial test

**Solution:**
- Verify user has full permissions for incident API
- Check network stability
- For OAuth, ensure token refresh is working

## Testing Different Authentication Methods

### Basic Authentication Test

```yaml
Authentication Type: Basic Authentication
Username: maxadmin
Password: your-password
Maximo URL: https://maximo.company.com
Organization ID: EAGLENA
```

Click "Test Connection" → Should see ✓

### API Key Test

```yaml
Authentication Type: API Key
API Key: your-api-key-here
Maximo URL: https://maximo.company.com
Organization ID: EAGLENA
```

Click "Test Connection" → Should see ✓

### OAuth 2.0 Test

```yaml
Authentication Type: OAuth 2.0
Token URL: https://maximo.company.com/oauth/token
Client ID: aiops-client
Client Secret: your-secret
Maximo URL: https://maximo.company.com
Organization ID: EAGLENA
```

Click "Test Connection" → Should see ✓

## Manual Testing (Without UI)

You can test the connection programmatically:

```java
// Create configuration
Configuration config = new Configuration();
config.setUrl("https://maximo.company.com");
config.setAuthType("basic");
config.setUsername("maxadmin");
config.setPassword("password");
config.setMaximoOrgId("EAGLENA");

// Create client and test
MaximoHttpClient client = new MaximoHttpClient(config);
boolean success = client.testConnection().get();

if (success) {
    System.out.println("✓ Connection successful");
} else {
    System.out.println("✗ Connection failed");
}
```

## Best Practices

1. **Always test before saving**: Don't skip the connection test
2. **Test with minimal permissions first**: Verify basic connectivity
3. **Test from the cluster**: Network access from OpenShift may differ from your machine
4. **Check logs**: Always review connector logs if test fails
5. **Verify organization access**: Ensure user has access to specified org/site

## Security Considerations

### What Gets Tested

✅ **Tested:**
- URL reachability
- Authentication validity
- API accessibility
- Basic permissions

❌ **NOT Tested:**
- Full permission set (only minimal query)
- Data quality
- Performance under load
- All API endpoints

### Credentials Security

- Credentials are **encrypted** in transit (HTTPS)
- Passwords are **masked** in UI
- Credentials are **stored encrypted** in Kubernetes secrets
- Test connection **doesn't log** sensitive data

## FAQ

**Q: How long does the test take?**
A: Usually 2-5 seconds. OAuth may take slightly longer (token acquisition).

**Q: Does the test create any data in Maximo?**
A: No, it only performs a read-only query.

**Q: Can I skip the test?**
A: No, the test is required before saving the integration.

**Q: What if my Maximo is behind a firewall?**
A: Ensure OpenShift cluster can reach Maximo. You may need to configure network policies or VPN.

**Q: Does the test work with self-signed certificates?**
A: Yes, but you may need to add the certificate to OpenShift's trust store.

**Q: Can I test without creating an integration?**
A: Yes, use the manual testing approach shown above, or use curl/Postman.

## Related Files

- **UI Schema**: [`connectorschema-maximo.yaml`](bundle-artifacts/prereqs/connectorschema-maximo.yaml:280)
- **Backend Logic**: [`TicketConnector.java`](src/main/java/com/ibm/aiops/connectors/template/TicketConnector.java:104)
- **HTTP Client**: [`MaximoHttpClient.java`](src/main/java/com/ibm/aiops/connectors/template/MaximoHttpClient.java:223)
- **Configuration Model**: [`Configuration.java`](src/main/java/com/ibm/aiops/connectors/template/model/Configuration.java:1)

## Support

If connection test continues to fail:

1. Check [`DEPLOYMENT-FIX.md`](DEPLOYMENT-FIX.md:1) for deployment issues
2. Review [`README-MAXIMO.md`](README-MAXIMO.md:1) for configuration details
3. Check connector logs: `oc logs -l app=ticket-template`
4. Verify Maximo API documentation for your version