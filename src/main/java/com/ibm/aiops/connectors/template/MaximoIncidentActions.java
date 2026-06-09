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
import java.net.http.HttpResponse;
import java.util.Iterator;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.ibm.aiops.connectors.template.model.Configuration;
import com.ibm.aiops.connectors.template.model.IssueModel;
import com.ibm.cp4waiops.connectors.sdk.JsonParsing;
import com.ibm.cp4waiops.connectors.sdk.actions.ActionDataDeserializationException;
import com.ibm.cp4waiops.connectors.sdk.actions.ActionRequest;
import com.ibm.cp4waiops.connectors.sdk.actions.ConnectorActionException;

import io.cloudevents.CloudEvent;
import io.micrometer.core.instrument.Counter;

/**
 * Handles incident actions (create, update, close) for IBM Maximo
 */
public class MaximoIncidentActions implements Runnable {
    
    static final Logger logger = Logger.getLogger(MaximoIncidentActions.class.getName());
    static final String ACTION_MAXIMO_RESPONSE = "cp4waiops-cartridge.itsmincidentresponse";
    
    private ConnectorAction action;
    private MaximoHttpClient maximoClient;
    
    public MaximoIncidentActions(ConnectorAction action) {
        this.action = action;
        this.maximoClient = new MaximoHttpClient(action.getConfiguration());
    }
    
    @Override
    public void run() {
        logger.log(Level.INFO, "Running Maximo Incident Action: " + action.actionType);
        
        switch (action.actionType) {
            case ConnectorConstants.ISSUE_CREATE:
                createIncident(action);
                break;
            case ConnectorConstants.ISSUE_UPDATE:
                updateIncident(action);
                break;
            case ConnectorConstants.ISSUE_CLOSE:
                closeIncident(action);
                break;
            default:
                logger.log(Level.WARNING, "Unknown action type: " + action.actionType);
        }
    }
    
    /**
     * Create a new incident in Maximo
     */
    private void createIncident(ConnectorAction action) {
        Counter actionCounter = action.getActionCounter();
        Counter actionErrorCounter = action.getActionErrorCounter();
        Configuration config = action.getConfiguration();
        TicketConnector connector = action.getConnector();
        ActionRequest request = action.getActionRequest();
        
        ObjectNode requestContent = null;
        try {
            requestContent = request.dataAs(ObjectNode.class);
        } catch (ActionDataDeserializationException e) {
            actionErrorCounter.increment();
            logger.log(Level.SEVERE, "Failed to deserialize request data", e);
            return;
        }
        
        try {
            ObjectNode responseJSON = createMaximoIncident(requestContent, config.getMappings(), config);
            logger.log(Level.INFO, "Maximo incident creation response: " + responseJSON);
            
            if (responseJSON.get("status").asText().equals("success")) {
                // Parse Maximo response
                String responseBody = responseJSON.get("data").asText();
                JsonNode data = new ObjectMapper().readTree(responseBody);
                
                // Extract incident details
                String ticketId = data.get("ticketid").asText();
                String ticketUid = data.get("ticketuid").asText();
                
                // Build permalink to Maximo incident
                String permalink = String.format("%s/maximo/ui/?event=loadapp&value=incident&additionalevent=useqbe&additionaleventvalue=ticketid=%s",
                        config.getUrl(), ticketId);
                
                // Create response for AIOps
                String response = IssueModel.getResponse(
                        ticketUid,
                        true,
                        "Created Maximo incident with ID: " + ticketId,
                        ticketId,
                        connector.getConnectorID(),
                        IssueModel.getStoryId(request.getData()),
                        "Successful",
                        permalink
                );
                
                // Emit cloud event back to AIOps
                CloudEvent ce = connector.createEvent(0, 
                        "com.ibm.sdlc.maximo.incident.create.response",
                        response,
                        new URI(permalink));
                connector.emitCloudEvent(ACTION_MAXIMO_RESPONSE, connector.getPartition(), ce);
                
                actionCounter.increment();
                logger.log(Level.INFO, "Successfully created Maximo incident: " + ticketId);
            } else {
                actionErrorCounter.increment();
                logger.log(Level.SEVERE, "Failed to create Maximo incident");
            }
        } catch (Exception e) {
            actionErrorCounter.increment();
            logger.log(Level.SEVERE, "Error creating Maximo incident", e);
        }
    }
    
    /**
     * Update an existing incident in Maximo
     */
    private void updateIncident(ConnectorAction action) {
        Counter actionCounter = action.getActionCounter();
        Counter actionErrorCounter = action.getActionErrorCounter();
        Configuration config = action.getConfiguration();
        ActionRequest request = action.getActionRequest();
        
        ObjectNode requestContent = null;
        try {
            requestContent = request.dataAs(ObjectNode.class);
        } catch (ActionDataDeserializationException e) {
            actionErrorCounter.increment();
            logger.log(Level.SEVERE, "Failed to deserialize request data", e);
            return;
        }
        
        try {
            // Get the Maximo ticket ID from the stored mapping
            String ticketId = IssueModel.getIssueId(request.getData());
            
            if (ticketId != null && !ticketId.isEmpty()) {
                ObjectNode responseJSON = updateMaximoIncident(requestContent, 
                        config.getMappings(), ticketId, config);
                logger.log(Level.INFO, "Maximo incident update response: " + responseJSON);
                
                if (responseJSON.get("status").asText().equals("success")) {
                    actionCounter.increment();
                    logger.log(Level.INFO, "Successfully updated Maximo incident: " + ticketId);
                } else {
                    actionErrorCounter.increment();
                    logger.log(Level.SEVERE, "Failed to update Maximo incident: " + ticketId);
                }
            } else {
                logger.log(Level.WARNING, "No Maximo ticket ID found for update");
                actionErrorCounter.increment();
            }
        } catch (Exception e) {
            actionErrorCounter.increment();
            logger.log(Level.SEVERE, "Error updating Maximo incident", e);
        }
    }
    
    /**
     * Close an incident in Maximo
     */
    private void closeIncident(ConnectorAction action) {
        Counter actionCounter = action.getActionCounter();
        Counter actionErrorCounter = action.getActionErrorCounter();
        Configuration config = action.getConfiguration();
        ActionRequest request = action.getActionRequest();
        
        ObjectNode requestContent = null;
        try {
            requestContent = request.dataAs(ObjectNode.class);
        } catch (ActionDataDeserializationException e) {
            actionErrorCounter.increment();
            logger.log(Level.SEVERE, "Failed to deserialize request data", e);
            return;
        }
        
        try {
            String ticketId = IssueModel.getIssueId(request.getData());
            
            if (ticketId != null && !ticketId.isEmpty()) {
                ObjectNode responseJSON = closeMaximoIncident(requestContent, 
                        config.getMappings(), ticketId, config);
                logger.log(Level.INFO, "Maximo incident close response: " + responseJSON);
                
                if (responseJSON.get("status").asText().equals("success")) {
                    actionCounter.increment();
                    logger.log(Level.INFO, "Successfully closed Maximo incident: " + ticketId);
                } else {
                    actionErrorCounter.increment();
                    logger.log(Level.SEVERE, "Failed to close Maximo incident: " + ticketId);
                }
            } else {
                logger.log(Level.WARNING, "No Maximo ticket ID found for closure");
                actionErrorCounter.increment();
            }
        } catch (Exception e) {
            actionErrorCounter.increment();
            logger.log(Level.SEVERE, "Error closing Maximo incident", e);
        }
    }
    
    /**
     * Create incident in Maximo via REST API
     */
    private ObjectNode createMaximoIncident(ObjectNode requestNode, String jsonata, 
            Configuration config) {
        ObjectNode responseJson = JsonNodeFactory.instance.objectNode();
        
        try {
            // Apply JSONata mapping
            String parsedJSON = JsonParsing.jsonataMap(requestNode.toString(), jsonata);
            logger.log(Level.INFO, "Mapped incident data: " + parsedJSON);
            
            JsonNode parsedContent = new ObjectMapper().readTree(parsedJSON);
            
            // Build Maximo incident object
            ObjectNode maximoIncident = JsonNodeFactory.instance.objectNode();
            
            // Copy all mapped fields
            Iterator<Map.Entry<String, JsonNode>> fields = parsedContent.fields();
            while (fields.hasNext()) {
                Map.Entry<String, JsonNode> field = fields.next();
                maximoIncident.set(field.getKey(), field.getValue());
            }
            
            // Ensure required Maximo fields
            if (!maximoIncident.has("orgid")) {
                maximoIncident.put("orgid", config.getMaximoOrgId());
            }
            if (!maximoIncident.has("siteid") && config.getMaximoSiteId() != null) {
                maximoIncident.put("siteid", config.getMaximoSiteId());
            }
            if (!maximoIncident.has("status")) {
                maximoIncident.put("status", "NEW");
            }
            
            String requestBody = new ObjectMapper().writeValueAsString(maximoIncident);
            logger.log(Level.INFO, "Creating Maximo incident with body: " + requestBody);
            
            // POST to Maximo
            HttpResponse<String> response = maximoClient.post(
                    "/oslc/os/mxincident", requestBody).get();
            
            if (response.statusCode() == 201 || response.statusCode() == 200) {
                logger.log(Level.INFO, "Maximo incident created successfully");
                responseJson.set("status", JsonNodeFactory.instance.textNode("success"));
                responseJson.set("data", JsonNodeFactory.instance.textNode(response.body()));
            } else {
                logger.log(Level.SEVERE, "Failed to create Maximo incident. Status: " + 
                        response.statusCode());
                logger.log(Level.SEVERE, "Response: " + response.body());
                responseJson.set("status", JsonNodeFactory.instance.textNode("error"));
                responseJson.set("message", JsonNodeFactory.instance.textNode(response.body()));
            }
        } catch (JsonProcessingException e) {
            responseJson.set("status", JsonNodeFactory.instance.textNode("error"));
            logger.log(Level.SEVERE, "JSON processing error", e);
        } catch (Exception e) {
            responseJson.set("status", JsonNodeFactory.instance.textNode("error"));
            logger.log(Level.SEVERE, "Error creating Maximo incident", e);
        }
        
        return responseJson;
    }
    
    /**
     * Update incident in Maximo via REST API
     */
    private ObjectNode updateMaximoIncident(ObjectNode requestNode, String jsonata, 
            String ticketId, Configuration config) {
        ObjectNode responseJson = JsonNodeFactory.instance.objectNode();
        
        try {
            // Apply JSONata mapping
            String parsedJSON = JsonParsing.jsonataMap(requestNode.toString(), jsonata);
            logger.log(Level.INFO, "Mapped update data: " + parsedJSON);
            
            JsonNode parsedContent = new ObjectMapper().readTree(parsedJSON);
            
            // Build update object
            ObjectNode updateData = JsonNodeFactory.instance.objectNode();
            Iterator<Map.Entry<String, JsonNode>> fields = parsedContent.fields();
            while (fields.hasNext()) {
                Map.Entry<String, JsonNode> field = fields.next();
                updateData.set(field.getKey(), field.getValue());
            }
            
            String requestBody = new ObjectMapper().writeValueAsString(updateData);
            logger.log(Level.INFO, "Updating Maximo incident " + ticketId + " with: " + requestBody);
            
            // PATCH to Maximo
            String path = "/oslc/os/mxincident/" + ticketId;
            HttpResponse<String> response = maximoClient.patch(path, requestBody).get();
            
            if (response.statusCode() == 200) {
                logger.log(Level.INFO, "Maximo incident updated successfully");
                responseJson.set("status", JsonNodeFactory.instance.textNode("success"));
                responseJson.set("data", JsonNodeFactory.instance.textNode(response.body()));
            } else {
                logger.log(Level.SEVERE, "Failed to update Maximo incident. Status: " + 
                        response.statusCode());
                logger.log(Level.SEVERE, "Response: " + response.body());
                responseJson.set("status", JsonNodeFactory.instance.textNode("error"));
            }
        } catch (JsonProcessingException e) {
            responseJson.set("status", JsonNodeFactory.instance.textNode("error"));
            throw new ConnectorActionException(e, 400);
        } catch (Exception e) {
            responseJson.set("status", JsonNodeFactory.instance.textNode("error"));
            logger.log(Level.SEVERE, "Error updating Maximo incident", e);
        }
        
        return responseJson;
    }
    
    /**
     * Close incident in Maximo by updating status
     */
    private ObjectNode closeMaximoIncident(ObjectNode requestNode, String jsonata, 
            String ticketId, Configuration config) {
        ObjectNode responseJson = JsonNodeFactory.instance.objectNode();
        
        try {
            // Build close request
            ObjectNode closeData = JsonNodeFactory.instance.objectNode();
            closeData.put("status", "RESOLVED");
            
            // Add close notes if provided in request
            if (requestNode.has("close_notes")) {
                closeData.put("description_longdescription", 
                        requestNode.get("close_notes").asText());
            }
            
            String requestBody = new ObjectMapper().writeValueAsString(closeData);
            logger.log(Level.INFO, "Closing Maximo incident " + ticketId + " with: " + requestBody);
            
            // PATCH to Maximo
            String path = "/maximo/oslc/os/mxincident/" + ticketId;
            HttpResponse<String> response = maximoClient.patch(path, requestBody).get();
            
            if (response.statusCode() == 200) {
                logger.log(Level.INFO, "Maximo incident closed successfully");
                responseJson.set("status", JsonNodeFactory.instance.textNode("success"));
                responseJson.set("data", JsonNodeFactory.instance.textNode(response.body()));
            } else {
                logger.log(Level.SEVERE, "Failed to close Maximo incident. Status: " + 
                        response.statusCode());
                logger.log(Level.SEVERE, "Response: " + response.body());
                responseJson.set("status", JsonNodeFactory.instance.textNode("error"));
            }
        } catch (JsonProcessingException e) {
            responseJson.set("status", JsonNodeFactory.instance.textNode("error"));
            throw new ConnectorActionException(e, 400);
        } catch (Exception e) {
            responseJson.set("status", JsonNodeFactory.instance.textNode("error"));
            logger.log(Level.SEVERE, "Error closing Maximo incident", e);
        }
        
        return responseJson;
    }
}

// Made with Bob
