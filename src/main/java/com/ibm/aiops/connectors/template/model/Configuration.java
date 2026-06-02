/***********************************************************************
 *
 *      IBM Confidential
 *
 *      (C) Copyright IBM Corp. 2023
 *
 *      5737-M96
 *
 **********************************************************************/

package com.ibm.aiops.connectors.template.model;

import lombok.Data;
import lombok.ToString;

/**
 * The model that represents the ConnectorConfiguration. If you have more properties to add to your connector's
 * configuration, add it here and ensure it is defined in your BundleManifest's schema
 */

// Configuration model for IBM Maximo connector
// Supports multiple authentication methods: Basic, API Key, and OAuth 2.0
@Data
@ToString(exclude = {"password", "apiKey", "oauthClientSecret"})
public class Configuration {
    protected boolean data_flow = true;
    protected String[] datasource_type = { "tickets" };
    
    // Historical data collection time range
    protected long start = 0;
    protected long end = 0;
    
    // Basic configuration
    protected String url;
    protected String description;
    protected String collectionMode;
    protected int issueSamplingRate = 5; // Default 5 minutes
    protected String mappings;
    
    // Authentication type: "basic", "apikey", or "oauth"
    protected String authType = "basic";
    
    // Basic Authentication
    protected String username;
    protected String password;
    
    // API Key Authentication
    protected String apiKey;
    
    // OAuth 2.0 Authentication
    protected String oauthTokenUrl;
    protected String oauthClientId;
    protected String oauthClientSecret;
    
    // Maximo-specific configuration
    protected String maximoOrgId = "EAGLENA"; // Default organization
    protected String maximoSiteId;
    
    // Legacy fields (kept for compatibility)
    protected String owner;
    protected String repo;
}
