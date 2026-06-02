/***********************************************************************
 *
 *      IBM Confidential
 *
 *      (C) Copyright IBM Corp. 2024
 *
 *      5737-M96
 *
 **********************************************************************/

package com.ibm.aiops.connectors.template;

import java.net.URI;
import java.net.URISyntaxException;
import java.net.http.HttpResponse;
import java.text.SimpleDateFormat;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Level;
import java.util.logging.Logger;

import org.json.JSONArray;
import org.json.JSONObject;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ibm.aiops.connectors.template.model.Configuration;
import com.ibm.cp4waiops.connectors.sdk.TicketAction;
import com.ibm.cp4waiops.connectors.sdk.actions.ConnectorActionException;
import com.ibm.cp4waiops.connectors.sdk.models.Ticket;

import io.micrometer.core.instrument.Counter;

/**
 * Polls IBM Maximo for incidents and emits them to AIOps
 * Supports both historical and live data collection modes
 */
public class MaximoIncidentPoller implements Runnable {
    
    static final Logger logger = Logger.getLogger(MaximoIncidentPoller.class.getName());
    
    // Maximo date format: ISO 8601
    static final String DATE_FORMAT_PATTERN = "yyyy-MM-dd'T'HH:mm:ss'Z'";
    
    private Counter actionCounter;
    private Counter actionErrorCounter;
    private Configuration config;
    private String collectionMode;
    private ScheduledExecutorService executorService = null;
    private TicketConnector connector;
    private AtomicBoolean stopDataCollection = new AtomicBoolean(false);
    private SimpleDateFormat sdf = new SimpleDateFormat(DATE_FORMAT_PATTERN);
    private TicketAction ticketAction;
    private MaximoHttpClient maximoClient;
    
    public MaximoIncidentPoller(ConnectorAction action) {
        this.actionCounter = action.getActionCounter();
        this.actionErrorCounter = action.getActionErrorCounter();
        this.config = action.getConfiguration();
        this.collectionMode = config.getCollectionMode();
        this.connector = action.getConnector();
        this.maximoClient = new MaximoHttpClient(config);
    }
    
    @Override
    public void run() {
        logger.log(Level.INFO, "Starting Maximo Incident Polling");
        
        HashMap<String, String> mapping = new HashMap<String, String>();
        ticketAction = new TicketAction(connector, mapping, ConnectorConstants.TICKET_TYPE, 
                config.getUrl(), collectionMode);
        
        actionCounter.increment();
        
        try {
            if (collectionMode.equals(ConnectorConstants.HISTORICAL)) {
                logger.log(Level.INFO, "Starting historical data collection from Maximo");
                fetchAndEmitIncidents();
                connector.triggerAlerts(ConnectorConstants.INSTANCE_HISTORICAL_DATACOLLECTION_CE_TYPE);
            } else {
                logger.log(Level.INFO, "Starting live data collection from Maximo");
                executorService = Executors.newSingleThreadScheduledExecutor();
                int samplingRate = config.getIssueSamplingRate() > 0 ? 
                        config.getIssueSamplingRate() : 5;
                executorService.scheduleAtFixedRate(this::fetchAndEmitIncidents, 0, 
                        samplingRate, TimeUnit.MINUTES);
            }
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Failed to collect data from Maximo", e);
            actionErrorCounter.increment();
        }
    }
    
    public void stop() {
        logger.log(Level.INFO, "Stopping Maximo incident polling");
        stopDataCollection.set(true);
        ticketAction.closeSearchBulkProcessor();
        
        if (executorService != null) {
            logger.log(Level.INFO, "Shutting down polling executor");
            executorService.shutdownNow();
            logger.log(Level.INFO, "Maximo incident polling stopped");
        }
    }
    
    private void fetchAndEmitIncidents() {
        if (stopDataCollection.get()) {
            logger.log(Level.INFO, "Data collection stopped, skipping fetch");
            return;
        }
        
        logger.log(Level.INFO, "Fetching incidents from Maximo");
        
        try {
            String oslcQuery = buildOSLCQuery();
            queryAllPages(oslcQuery);
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error fetching incidents from Maximo", e);
            actionErrorCounter.increment();
        }
    }
    
    /**
     * Build OSLC query based on collection mode and date range
     */
    private String buildOSLCQuery() {
        StringBuilder query = new StringBuilder("/maximo/oslc/os/mxincident?");
        
        // Select fields to retrieve
        query.append("oslc.select=ticketid,description,description_longdescription,");
        query.append("status,reportedby,affectedperson,reportdate,changedate,");
        query.append("siteid,orgid,classstructureid,ticketuid,owner,ownergroup,");
        query.append("activityid,assetnum,location,priority,severity");
        
        // Build where clause based on collection mode
        if (collectionMode.equals(ConnectorConstants.HISTORICAL) && config.getStart() > 0) {
            Date startDate = new Date(config.getStart());
            Date endDate = config.getEnd() > 0 ? new Date(config.getEnd()) : new Date();
            
            String startStr = sdf.format(startDate);
            String endStr = sdf.format(endDate);
            
            query.append("&oslc.where=reportdate>=\"").append(startStr).append("\"");
            query.append(" and reportdate<=\"").append(endStr).append("\"");
            query.append(" and status in [\"CLOSED\",\"RESOLVED\"]");
            
            logger.log(Level.INFO, "Historical query from " + startStr + " to " + endStr);
        } else {
            // Live mode - get recent incidents
            LocalDateTime currentDateTime = LocalDateTime.now();
            int samplingRate = config.getIssueSamplingRate() > 0 ? 
                    config.getIssueSamplingRate() : 5;
            LocalDateTime modifiedDateTime = currentDateTime.minusMinutes(samplingRate + 1);
            
            DateTimeFormatter formatter = DateTimeFormatter.ofPattern(DATE_FORMAT_PATTERN);
            String dateStr = modifiedDateTime.format(formatter);
            
            query.append("&oslc.where=changedate>=\"").append(dateStr).append("\"");
            
            logger.log(Level.INFO, "Live query since: " + dateStr);
        }
        
        // Add organization filter if specified
        if (config.getMaximoOrgId() != null && !config.getMaximoOrgId().isEmpty()) {
            query.append(" and orgid=\"").append(config.getMaximoOrgId()).append("\"");
        }
        
        // Add site filter if specified
        if (config.getMaximoSiteId() != null && !config.getMaximoSiteId().isEmpty()) {
            query.append(" and siteid=\"").append(config.getMaximoSiteId()).append("\"");
        }
        
        // Page size
        query.append("&oslc.pageSize=100");
        
        return query.toString();
    }
    
    /**
     * Query all pages of results from Maximo
     */
    protected void queryAllPages(String initialQuery) {
        try {
            String currentQuery = initialQuery;
            boolean hasMorePages = true;
            int pageCount = 0;
            
            while (hasMorePages && !stopDataCollection.get()) {
                pageCount++;
                logger.log(Level.INFO, "Fetching page " + pageCount);
                
                HttpResponse<String> response = maximoClient.get(currentQuery).get();
                
                if (response.statusCode() != 200) {
                    logger.log(Level.WARNING, "Failed to fetch incidents. Status: " + 
                            response.statusCode());
                    logger.log(Level.WARNING, "Response: " + response.body());
                    break;
                }
                
                String responseBody = response.body();
                JSONObject jsonResponse = new JSONObject(responseBody);
                
                // Parse OSLC response
                if (jsonResponse.has("rdfs:member")) {
                    JSONArray incidents = jsonResponse.getJSONArray("rdfs:member");
                    int incidentCount = incidents.length();
                    
                    logger.log(Level.INFO, "Processing " + incidentCount + " incidents");
                    
                    if (incidentCount > 0) {
                        ArrayList<Ticket> ticketList = new ArrayList<Ticket>();
                        
                        for (int i = 0; i < incidentCount; i++) {
                            JSONObject incident = incidents.getJSONObject(i);
                            processIncident(incident, ticketList);
                            actionCounter.increment();
                        }
                        
                        if (ticketList.size() > 0) {
                            ticketAction.insertIncident(ticketList);
                            logger.log(Level.INFO, "Inserted " + ticketList.size() + " incidents");
                        }
                    }
                }
                
                // Check for next page
                if (jsonResponse.has("oslc:responseInfo")) {
                    JSONObject responseInfo = jsonResponse.getJSONObject("oslc:responseInfo");
                    if (responseInfo.has("oslc:nextPage")) {
                        String nextPageUrl = responseInfo.getString("oslc:nextPage");
                        // Extract just the query part
                        URI uri = new URI(nextPageUrl);
                        currentQuery = uri.getPath() + "?" + uri.getQuery();
                        logger.log(Level.INFO, "Next page available");
                    } else {
                        hasMorePages = false;
                        logger.log(Level.INFO, "No more pages available");
                    }
                } else {
                    hasMorePages = false;
                }
            }
            
            logger.log(Level.INFO, "Completed fetching " + pageCount + " pages from Maximo");
            
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error querying Maximo pages", e);
            actionErrorCounter.increment();
        }
    }
    
    /**
     * Process a single Maximo incident and convert to AIOps Ticket format
     */
    protected void processIncident(JSONObject maximoIncident, ArrayList<Ticket> ticketList) {
        try {
            Ticket ticket = new Ticket();
            JSONObject ticketJson = new JSONObject();
            
            // Required fields
            String ticketId = maximoIncident.optString("ticketid", "");
            String ticketUid = maximoIncident.optString("ticketuid", ticketId);
            
            ticketJson.put(Ticket.key_sys_id, ticketUid);
            ticketJson.put(Ticket.key_number, ticketId);
            
            // Description fields
            ticketJson.put(Ticket.key_short_description, 
                    maximoIncident.optString("description", ""));
            
            String longDesc = "";
            if (maximoIncident.has("description_longdescription")) {
                longDesc = maximoIncident.optString("description_longdescription", "");
            }
            ticketJson.put(Ticket.key_description, longDesc);
            
            // Status mapping
            String status = maximoIncident.optString("status", "NEW");
            ticketJson.put(Ticket.key_state, mapMaximoStatus(status));
            ticketJson.put(Ticket.key_close_code, status);
            
            // People fields
            ticketJson.put(Ticket.key_opened_by, 
                    maximoIncident.optString("reportedby", ""));
            ticketJson.put(Ticket.key_assigned_to, 
                    maximoIncident.optString("owner", ""));
            ticketJson.put(Ticket.key_caller_id, 
                    maximoIncident.optString("affectedperson", ""));
            ticketJson.put(Ticket.key_sys_created_by, 
                    maximoIncident.optString("reportedby", ""));
            
            // Dates
            ticketJson.put(Ticket.key_sys_created_on, 
                    maximoIncident.optString("reportdate", ""));
            ticketJson.put(Ticket.key_sys_updated_on, 
                    maximoIncident.optString("changedate", ""));
            ticketJson.put(Ticket.key_opened_at, 
                    maximoIncident.optString("reportdate", ""));
            
            // Organization and site
            ticketJson.put(Ticket.key_sys_domain, 
                    maximoIncident.optString("orgid", ""));
            ticketJson.put(Ticket.key_business_service, 
                    maximoIncident.optString("siteid", ""));
            
            // Priority and severity
            String priority = maximoIncident.optString("priority", "");
            ticketJson.put(Ticket.key_impact, priority);
            
            // Additional fields
            ticketJson.put(Ticket.key_sys_class_name, "Incident");
            ticketJson.put(Ticket.key_source_name, ConnectorConstants.TICKET_TYPE);
            ticketJson.put(Ticket.key_instance, getDomainName(config.getUrl()));
            ticketJson.put(Ticket.key_connectionmode, collectionMode);
            ticketJson.put(Ticket.key_connection_id, connector.getConnectorID());
            
            // Build source URL
            String sourceUrl = String.format("%s/maximo/ui/?event=loadapp&value=incident&additionalevent=useqbe&additionaleventvalue=ticketid=%s",
                    config.getUrl(), ticketId);
            ticketJson.put(Ticket.key_source, sourceUrl);
            
            // For historical mode, only include closed/resolved incidents
            if (collectionMode.equals(ConnectorConstants.HISTORICAL)) {
                if (status.equalsIgnoreCase("CLOSED") || status.equalsIgnoreCase("RESOLVED")) {
                    ObjectMapper objectMapper = new ObjectMapper();
                    ticket = objectMapper.readValue(ticketJson.toString(), Ticket.class);
                    ticketList.add(ticket);
                }
            } else {
                // For live mode, include all incidents
                ObjectMapper objectMapper = new ObjectMapper();
                ticket = objectMapper.readValue(ticketJson.toString(), Ticket.class);
                ticketList.add(ticket);
            }
            
        } catch (JsonProcessingException e) {
            logger.log(Level.WARNING, "Failed to process Maximo incident", e);
            actionErrorCounter.increment();
        } catch (Exception e) {
            logger.log(Level.WARNING, "Error processing incident", e);
            actionErrorCounter.increment();
        }
    }
    
    /**
     * Map Maximo status to AIOps status
     */
    private String mapMaximoStatus(String maximoStatus) {
        if (maximoStatus == null) return "Open";
        
        switch (maximoStatus.toUpperCase()) {
            case "CLOSED":
            case "RESOLVED":
                return "Closed";
            case "INPROG":
            case "PENDING":
                return "In Progress";
            case "NEW":
            default:
                return "Open";
        }
    }
    
    /**
     * Extract domain name from URL
     */
    public static String getDomainName(String url) throws URISyntaxException {
        URI uri = new URI(url);
        String domain = uri.getHost();
        return domain != null ? (domain.startsWith("www.") ? domain.substring(4) : domain) : "";
    }
}

// Made with Bob
