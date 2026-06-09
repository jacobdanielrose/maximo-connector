# Next Steps - Now That Schema is Deployed

## Current Status ✅

- ✅ ConnectorSchema `maximo-connector` is now deployed
- ✅ Connector pod should be running
- ⏳ Need to create integration through UI
- ⏳ Secret will be auto-created
- ⏳ Authentication will work

## Step-by-Step: Create the Integration

### 1. Access AIOps UI

Navigate to your CP4AIOps instance and log in.

### 2. Go to Integrations

- Click on **Integrations** in the left navigation
- Click **Add Integration** button

### 3. Find IBM Maximo

- In the integration catalog, search for "Maximo"
- You should now see **IBM Maximo** as an available integration
- Click on it to start configuration

### 4. Fill in Connection Details

**Basic Information:**
- **Connection Name**: Give it a unique name (e.g., `maximo-prod`, `maximo-test`)
- **Description**: Optional description of this integration

**Maximo Configuration:**
- **Maximo URL**: Your Maximo base URL
  - Example: `https://maximo.example.com`
  - Example: `https://your-mas-instance.com`
  - Do NOT include `/maximo` or `/api` at the end

**Authentication Type:** Choose one:

#### Option A: Basic Authentication (Most Common)
- Select: **Basic Authentication**
- **Username**: Your Maximo username
- **Password**: Your Maximo password

#### Option B: API Key (For MAS)
- Select: **API Key**
- **API Key**: Your Maximo API key
  - Get this from Maximo Administration → Integration → API Keys

#### Option C: OAuth 2.0 (If Configured)
- Select: **OAuth 2.0**
- **Token URL**: OAuth token endpoint (e.g., `https://maximo.example.com/oauth/token`)
- **Client ID**: Your OAuth client ID
- **Client Secret**: Your OAuth client secret

**Maximo Settings:**
- **Organization ID**: Your Maximo organization (default: `EAGLENA`)
  - Check with your Maximo admin if unsure
- **Site ID**: Optional, leave blank unless required

**Deployment Type:**
- Select: **Local** (recommended for most deployments)

### 5. Test Connection

- Click **Test Connection** button
- Wait for the test to complete
- You should see a success message

**If test fails:**
- Verify Maximo URL is correct
- Verify credentials are correct
- Check network connectivity from CP4AIOps to Maximo
- See troubleshooting section below

### 6. Configure Data Collection (Optional)

If you want to collect historical incidents:
- Toggle **Data Flow** to ON
- Select **Historical** mode
- Set start and end dates

For live monitoring:
- Toggle **Data Flow** to ON
- Select **Live** mode
- Set **Incident Sampling Rate** (default: 5 minutes)

### 7. Save the Integration

- Click **Save** or **Create** button
- Wait for the integration to be created (5-10 seconds)

## Verification Steps

### 1. Check Secret Was Created

```bash
NAMESPACE=cp4waiops  # adjust if different

# Check if secret exists
oc get secret connector -n $NAMESPACE

# View secret details
oc get secret connector -n $NAMESPACE -o yaml
```

**Expected:** Secret should exist with keys: `id`, `client-id`, `client-secret`

### 2. Watch Connector Logs

```bash
# Watch logs in real-time
oc logs -n $NAMESPACE -l app=ticket-template -f
```

**Look for these SUCCESS indicators:**
```
[INFO] starting configuration consume stream: channel=grpc-connector-configuration-updates-channel
[INFO] CloudEventProducer created
[INFO] starting manager
[INFO] event cycle starting
```

**Should NOT see:**
```
UNAUTHENTICATED: unable to authenticate client
```

### 3. Check Integration Status in UI

- Go back to Integrations page
- Find your Maximo integration
- Status should show: **Connected** or **Active**

### 4. Test Incident Creation (Optional)

If you want to test creating an incident in Maximo:

1. In AIOps, create a test alert or story
2. Configure a policy to create incidents in Maximo
3. Trigger the policy
4. Check Maximo for the created incident

## Troubleshooting

### Secret Not Created

If the secret is still not created after 30 seconds:

```bash
# Check connector configuration status
oc get connectorconfiguration -n $NAMESPACE

# Check for errors
oc describe connectorconfiguration <your-config-name> -n $NAMESPACE

# Check operator logs
oc logs -n $NAMESPACE -l app.kubernetes.io/name=connector-operator --tail=100
```

### Still Getting UNAUTHENTICATED Errors

If you still see authentication errors after creating the integration:

```bash
# Restart the connector pod
oc delete pod -n $NAMESPACE -l app=ticket-template

# Wait for new pod to start
oc get pods -n $NAMESPACE -l app=ticket-template -w

# Watch logs again
oc logs -n $NAMESPACE -l app=ticket-template -f
```

### Maximo Connection Test Fails

If the connection test fails with Maximo errors (not gRPC errors):

**HTTP 401 Unauthorized:**
- Verify username/password or API key is correct
- Check if account is locked or expired

**HTTP 403 Forbidden:**
- User doesn't have permissions in Maximo
- Check Maximo security groups and roles

**HTTP 302 Redirect:**
- Maximo is using OIDC/SSO authentication
- Use API Key authentication instead of Basic Auth

**Connection Timeout:**
- Check network connectivity
- Verify firewall rules allow traffic from CP4AIOps to Maximo
- Check if Maximo URL is correct

**SSL/TLS Errors:**
- The connector trusts all certificates by default
- If still having issues, see: [`SSL-CERTIFICATE-FIX.md`](SSL-CERTIFICATE-FIX.md)

## Success Indicators

You'll know everything is working when:

1. ✅ Secret `connector` exists in your namespace
2. ✅ Connector logs show "starting configuration consume stream"
3. ✅ NO `UNAUTHENTICATED` errors in logs
4. ✅ Integration status shows "Connected" in UI
5. ✅ If in live mode, logs show periodic polling of Maximo
6. ✅ Test incident creation works (if configured)

## What Happens Next

Once authentication is working:

1. **Live Mode**: Connector will poll Maximo every N minutes for new/updated incidents
2. **Historical Mode**: Connector will fetch incidents from the specified date range
3. **Incident Creation**: AIOps can create incidents in Maximo via policies
4. **AI Training**: Collected incidents can be used for Similar Incident and Change Risk models

## Additional Configuration

After basic setup is working, you may want to:

1. **Configure Field Mappings**: Customize how AIOps incidents map to Maximo fields
2. **Set Up Policies**: Define when to create/update incidents in Maximo
3. **Train AI Models**: Use collected incidents for AI training
4. **Configure Webhooks**: Set up Maximo to push updates to AIOps

See the main README for details on these advanced configurations.

## Need Help?

If you're still having issues:

1. Check all the troubleshooting guides:
   - [`CRITICAL-FIX-APPLY-NOW.md`](CRITICAL-FIX-APPLY-NOW.md)
   - [`NO-SECRET-CREATED-FIX.md`](NO-SECRET-CREATED-FIX.md)
   - [`GRPC-AUTH-TROUBLESHOOTING.md`](GRPC-AUTH-TROUBLESHOOTING.md)

2. Run the diagnostic script:
   ```bash
   ./diagnose-grpc-auth.sh <namespace>
   ```

3. Collect logs for support:
   ```bash
   # Connector logs
   oc logs -n $NAMESPACE -l app=ticket-template --tail=500 > connector-logs.txt
   
   # Connector bridge logs
   oc logs -n $NAMESPACE -l app.kubernetes.io/name=connector-bridge --tail=500 > bridge-logs.txt
   
   # Configuration
   oc get connectorconfiguration -n $NAMESPACE -o yaml > connector-config.yaml
   ```

---

**You're almost there! Just create the integration through the UI and you should be good to go.** 🚀