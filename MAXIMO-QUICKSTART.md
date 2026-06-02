# IBM Maximo Connector - Quick Start Guide

This guide will help you quickly set up and configure the IBM Maximo connector for IBM Cloud Pak for AIOps.

## Prerequisites Checklist

- [ ] IBM Cloud Pak for AIOps 4.3.0+ installed
- [ ] IBM Maximo instance accessible
- [ ] Maximo credentials ready
- [ ] OpenShift CLI (`oc`) configured
- [ ] GitHub token for bundle manifest

## 5-Minute Setup

### 1. Create GitHub Secret (1 min)

```bash
oc create secret generic maximo-github-token \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_TOKEN
```

### 2. Deploy Bundle Manifest (1 min)

```bash
oc apply -f bundlemanifest-maximo.yaml
```

### 3. Verify Deployment (1 min)

```bash
# Check bundle manifest status
oc get bundlemanifest maximo-connector

# Wait for "Configured" status
# If needed, force UI refresh:
oc delete pod -l app.kubernetes.io/name=aiops-connections-ui
```

### 4. Create Integration in UI (2 min)

1. Navigate to **Integrations** in AIOps UI
2. Search for "**IBM Maximo**"
3. Click **Add Integration**

## Configuration Wizard

### Step 1: Connection Details

**Basic Information:**
- **Name**: `maximo-prod` (or your preferred name)
- **Description**: "Production Maximo integration"
- **Maximo URL**: `https://your-maximo-instance.com`

**Authentication** (choose one):

**Option A: Basic Authentication**
```
Username: your-maximo-username
Password: your-maximo-password
```

**Option B: API Key**
```
API Key: your-maximo-api-key
```

**Option C: OAuth 2.0**
```
Token URL: https://your-maximo-instance.com/oauth/token
Client ID: your-client-id
Client Secret: your-client-secret
```

**Maximo Configuration:**
- **Organization ID**: `EAGLENA` (or your org)
- **Site ID**: (optional)

**Deployment Type:**
- Select **Local** (recommended) or **Remote**

Click **Test Connection** to verify.

### Step 2: Field Mapping (Optional)

Use the default mapping or customize:

```jsonata
({
    "description": $join([
        "Incident from AIOps: ", $string(incident.id),
        "\nTitle: ", $string(incident.title),
        "\nDescription: ", $string(incident.description)
    ]),
    "reportedby": "AIOPS",
    "status": "NEW",
    "orgid": "EAGLENA"
})
```

### Step 3: Data Collection (Optional)

**For AI Training (Historical Mode):**
- Enable **Data Flow**: ON
- Select **Historical**
- **Start Date**: 6 months ago
- **End Date**: Today
- Click **Done**

**For Live Monitoring:**
- Enable **Data Flow**: ON
- Select **Live**
- **Sampling Rate**: 5 minutes
- Click **Done**

## Verify Integration

### Check Connector Status

```bash
# View connector pods
oc get pods -l app.kubernetes.io/name=maximo-connector

# Check logs
oc logs -l app.kubernetes.io/name=maximo-connector --tail=50
```

### Test Incident Creation

1. Create a test alert in AIOps
2. Create a policy to generate an incident
3. Verify incident appears in Maximo

## Common Authentication Scenarios

### Scenario 1: Maximo Application Suite (MAS) with API Key

```yaml
Authentication Type: API Key
API Key: <your-mas-api-key>
Maximo URL: https://your-tenant.suite.maximo.com
Organization ID: <your-org-id>
```

### Scenario 2: Traditional Maximo with Basic Auth

```yaml
Authentication Type: Basic Authentication
Username: maxadmin
Password: <password>
Maximo URL: https://maximo.company.com
Organization ID: EAGLENA
```

### Scenario 3: Maximo with OAuth 2.0

```yaml
Authentication Type: OAuth 2.0
Token URL: https://maximo.company.com/oauth/token
Client ID: aiops-client
Client Secret: <secret>
Maximo URL: https://maximo.company.com
```

## Training AI Models

### Similar Incidents

1. Run historical collection (6+ months of closed incidents)
2. Navigate to **AI Model Management** → **Similar Incidents**
3. Click **Configure**
4. Select your Maximo integration as data source
5. Click **Pre-check data** → **Train** → **Deploy**

### Change Risk

1. Ensure change request data is collected
2. Navigate to **AI Model Management** → **Change Risk**
3. Follow the same training process

## Troubleshooting Quick Fixes

### Connection Test Fails

```bash
# Test connectivity from cluster
oc run curl-test --image=curlimages/curl -it --rm -- \
  curl -v https://your-maximo-instance.com

# Check DNS resolution
oc run nslookup-test --image=busybox -it --rm -- \
  nslookup your-maximo-instance.com
```

### No Incidents Collected

```bash
# Check connector logs for errors
oc logs -l app.kubernetes.io/name=maximo-connector | grep -i error

# Verify Maximo query
# The connector uses: /maximo/oslc/os/mxincident
```

### Authentication Errors

1. Verify credentials in Maximo UI
2. Check user has required permissions
3. For OAuth, verify token URL is correct
4. Review connector logs for specific error messages

## Next Steps

- [ ] Set up policies for automatic incident creation
- [ ] Configure Slack integration for notifications
- [ ] Train Similar Incidents AI model
- [ ] Train Change Risk AI model
- [ ] Set up runbook automation
- [ ] Configure incident enrichment

## Useful Commands

```bash
# View all integrations
oc get connectorconfigurations

# Get specific integration details
oc get connectorconfiguration <integration-name> -o yaml

# Restart connector
oc delete pod -l app.kubernetes.io/name=maximo-connector

# View Kafka topics
oc get kafkatopics | grep incident

# Check Elasticsearch indices
curl -k -u $EL_USER:$EL_PWD https://localhost:9200/_cat/indices | grep snow
```

## Support Resources

- **Documentation**: [IBM Cloud Pak for AIOps Docs](https://ibm.biz/int-maximo)
- **Connector Logs**: `oc logs -l app.kubernetes.io/name=maximo-connector`
- **Maximo API Docs**: Check your Maximo instance `/maximo/oslc/doc`
- **Community**: IBM Cloud Pak User Group

## Security Best Practices

1. **Use Secrets**: Never hardcode credentials
2. **Rotate Keys**: Regularly rotate API keys and passwords
3. **Least Privilege**: Use service accounts with minimal permissions
4. **Network Security**: Use TLS/SSL for all connections
5. **Audit Logs**: Enable and monitor Maximo audit logs

---

**Need Help?** Check the full [README-MAXIMO.md](README-MAXIMO.md) for detailed documentation.