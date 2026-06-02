# IBM Maximo Connector for IBM Cloud Pak for AIOps

This connector integrates IBM Maximo with IBM Cloud Pak for AIOps to enable automated incident management, AI-powered similar incident detection, and change risk assessment.

## Features

- **Multiple Authentication Methods**: Supports Basic Auth, API Key, and OAuth 2.0
- **Bidirectional Integration**: 
  - Poll incidents from Maximo (historical and live modes)
  - Create incidents in Maximo from AIOps
  - Update incidents in Maximo
  - Close incidents in Maximo
- **AI Training Support**: 
  - Similar Incident detection
  - Change Risk assessment
- **Flexible Configuration**: Support for multiple Maximo deployments (MAS and traditional)

## Architecture

The connector follows the standard CP4AIOps connector framework architecture:

```
AIOps UI → Connector Manager → Connector Bridge (gRPC) → Maximo Connector → IBM Maximo
                                                              ↓
                                                         Kafka Topics
                                                              ↓
                                                    AI Models & Elasticsearch
```

## Prerequisites

1. IBM Cloud Pak for AIOps 4.3.0 or later
2. IBM Maximo instance (Application Suite or traditional)
3. Maximo credentials (username/password, API key, or OAuth credentials)
4. Network connectivity from CP4AIOps to Maximo instance

## Installation

### Step 1: Create GitHub Secret

Create a secret for pulling the bundle manifest:

```bash
oc create secret generic maximo-github-token \
  --from-literal=username=<GITHUB_USERNAME> \
  --from-literal=password=<GITHUB_TOKEN>
```

### Step 2: Deploy the Bundle Manifest

```bash
oc apply -f bundlemanifest-maximo.yaml
```

### Step 3: Verify Deployment

```bash
oc get bundlemanifest | grep maximo-connector
```

Expected output:
```
maximo-connector    Configured
```

### Step 4: Refresh UI (if needed)

The UI may take 5-10 minutes to refresh. To force a refresh:

```bash
oc delete pod -l app.kubernetes.io/name=aiops-connections-ui
```

## Configuration

### Authentication Methods

#### Basic Authentication
- **Username**: Your Maximo username
- **Password**: Your Maximo password

#### API Key Authentication
- **API Key**: Your Maximo API key

#### OAuth 2.0 Authentication
- **Token URL**: OAuth token endpoint (e.g., `https://maximo.example.com/oauth/token`)
- **Client ID**: OAuth client ID
- **Client Secret**: OAuth client secret

### Maximo Configuration

- **Maximo URL**: Base URL of your Maximo instance (e.g., `https://maximo.example.com`)
- **Organization ID**: Maximo organization (default: `EAGLENA`)
- **Site ID**: Optional site identifier

### Data Collection Modes

#### Live Mode
- Continuously polls Maximo for new/updated incidents
- Configurable sampling rate (1-60 minutes, default: 5 minutes)
- Suitable for real-time incident synchronization

#### Historical Mode
- One-time collection of historical incidents
- Specify start and end dates
- Used for AI model training
- Only collects closed/resolved incidents

## Field Mapping

The connector uses JSONata for flexible field mapping. Default mapping:

```jsonata
({
    "description": $join(["Incident Id:", $string(incident.id),
                   "\nAIOPS Incident Overview URL: https://", $string(URL_PREFIX), 
                   "/aiops/default/resolution-hub/incidents/all/", $string(incident.id), "/overview",
                   "\nStatus: ", $string(incident.state),
                   "\nDescription: ", $string(incident.description)]),
    "description_longdescription": $string(incident.description),
    "reportedby": "AIOPS",
    "affectedperson": "AIOPS",
    "status": "NEW",
    "reportdate": $now(),
    "siteid": $string(SITE_ID),
    "orgid": $string(ORG_ID)
})
```

### Customizing Field Mappings

You can customize the mapping to match your Maximo configuration:

1. In the integration wizard, go to the "Field Mapping" step
2. Modify the JSONata expression to map AIOps fields to Maximo fields
3. Available AIOps incident fields:
   - `incident.id` - Incident ID
   - `incident.title` - Incident title
   - `incident.description` - Incident description
   - `incident.state` - Incident state
   - `incident.priority` - Priority
   - `incident.severity` - Severity

## Maximo API Endpoints Used

The connector interacts with the following Maximo OSLC REST API endpoints:

- **GET** `/maximo/oslc/os/mxincident` - Query incidents
- **POST** `/maximo/oslc/os/mxincident` - Create incident
- **PATCH** `/maximo/oslc/os/mxincident/{ticketid}` - Update incident

## AI Model Training

### Similar Incident Training

1. Configure the connector in historical mode
2. Set date range to collect at least 6 months of closed incidents
3. Run the integration to collect data
4. Navigate to AI Model Management → Similar Incidents
5. Follow the training wizard
6. Deploy the model

### Change Risk Training

1. Ensure change request data is available in Maximo
2. Configure historical collection for change requests
3. Navigate to AI Model Management → Change Risk
4. Follow the training wizard
5. Deploy the model

## Troubleshooting

### Connection Test Fails

1. Verify Maximo URL is correct and accessible
2. Check authentication credentials
3. Verify network connectivity from CP4AIOps to Maximo
4. Check Maximo logs for authentication errors

### No Incidents Collected

1. Verify the date range in historical mode
2. Check organization and site ID filters
3. Verify incidents exist in Maximo for the specified criteria
4. Check connector logs:
   ```bash
   oc logs -l app.kubernetes.io/name=maximo-connector
   ```

### Incident Creation Fails

1. Verify field mappings are correct
2. Check required Maximo fields are populated
3. Verify user has permissions to create incidents in Maximo
4. Review Maximo API error messages in connector logs

## Development

### Local Development

1. Set up port forwarding to Elasticsearch:
   ```bash
   export EL_USER=`oc get secret iaf-system-elasticsearch-es-default-user -o go-template --template="{{.data.username|base64decode}}"`
   export EL_PWD=`oc get secret iaf-system-elasticsearch-es-default-user -o go-template --template="{{.data.password|base64decode}}"`
   kubectl port-forward iaf-system-elasticsearch-es-aiops-0 9200:9200
   ```

2. Create elastic credentials:
   ```bash
   mkdir elastic
   echo "localhost" > elastic/hostname
   echo "9200" > elastic/port
   echo $EL_USER > elastic/username
   echo $EL_PWD > elastic/password
   ```

3. Run locally:
   ```bash
   export SERVICE_BINDING_ROOT=$(pwd)
   mvn liberty:run
   ```

### Building the Connector

```bash
mvn clean package
```

### Running Tests

```bash
mvn test
```

## File Structure

```
maximo-connector/
├── src/main/java/com/ibm/aiops/connectors/template/
│   ├── MaximoHttpClient.java          # HTTP client with multi-auth support
│   ├── MaximoIncidentPoller.java      # Incident polling logic
│   ├── MaximoIncidentActions.java     # Create/Update/Close actions
│   ├── TicketConnector.java           # Main connector class
│   ├── Configuration.java             # Configuration model
│   └── ...
├── bundle-artifacts/
│   ├── prereqs/
│   │   └── connectorschema-maximo.yaml  # UI schema definition
│   └── connector/
│       └── deployment.yaml              # Kubernetes deployment
├── bundlemanifest-maximo.yaml         # Bundle manifest
├── pom.xml                            # Maven configuration
└── README-MAXIMO.md                   # This file
```

## API Reference

### MaximoHttpClient

Handles HTTP communication with Maximo REST API.

**Methods:**
- `get(String path)` - GET request
- `post(String path, String body)` - POST request
- `patch(String path, String body)` - PATCH request
- `testConnection()` - Test connectivity

### MaximoIncidentPoller

Polls Maximo for incidents.

**Methods:**
- `run()` - Start polling
- `stop()` - Stop polling
- `fetchAndEmitIncidents()` - Fetch and emit incidents

### MaximoIncidentActions

Handles incident actions.

**Methods:**
- `createIncident()` - Create incident in Maximo
- `updateIncident()` - Update incident in Maximo
- `closeIncident()` - Close incident in Maximo

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review connector logs
3. Consult IBM Cloud Pak for AIOps documentation
4. Contact IBM Support

## License

IBM Confidential
(C) Copyright IBM Corp. 2024
5737-M96

## Contributing

This connector is based on the IBM CP4AIOps Ticket Connector Template.
For contributions, follow IBM's internal development guidelines.