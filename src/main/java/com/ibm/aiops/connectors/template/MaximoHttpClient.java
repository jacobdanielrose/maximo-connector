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

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Base64;
import java.util.concurrent.CompletableFuture;
import java.util.logging.Level;
import java.util.logging.Logger;

import org.json.JSONObject;

import com.ibm.aiops.connectors.template.model.Configuration;

/**
 * HTTP client for IBM Maximo REST API with support for multiple authentication methods:
 * - Basic Authentication (username/password)
 * - API Key Authentication
 * - OAuth 2.0 Authentication
 */
public class MaximoHttpClient {
    static final Logger logger = Logger.getLogger(MaximoHttpClient.class.getName());
    
    private HttpClient httpClient;
    private String baseUrl;
    private String authType;
    private String authHeader;
    private String oauthToken;
    private long oauthTokenExpiry = 0;
    
    // OAuth configuration
    private String oauthTokenUrl;
    private String oauthClientId;
    private String oauthClientSecret;
    
    // Maximo configuration
    private String maximoOrgId;
    private String maximoSiteId;
    
    public MaximoHttpClient(Configuration config) {
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(30))
                .build();
        
        this.baseUrl = config.getUrl().replaceAll("/$", "");
        this.authType = config.getAuthType() != null ? config.getAuthType() : "basic";
        this.maximoOrgId = config.getMaximoOrgId();
        this.maximoSiteId = config.getMaximoSiteId();
        
        // Initialize authentication based on type
        initializeAuth(config);
    }
    
    private void initializeAuth(Configuration config) {
        switch (authType.toLowerCase()) {
            case "basic":
                String credentials = config.getUsername() + ":" + config.getPassword();
                String encodedCredentials = Base64.getEncoder()
                        .encodeToString(credentials.getBytes(StandardCharsets.UTF_8));
                this.authHeader = "Basic " + encodedCredentials;
                logger.log(Level.INFO, "Initialized Basic Authentication");
                break;
                
            case "apikey":
                this.authHeader = "apikey " + config.getApiKey();
                logger.log(Level.INFO, "Initialized API Key Authentication");
                break;
                
            case "oauth":
                this.oauthTokenUrl = config.getOauthTokenUrl();
                this.oauthClientId = config.getOauthClientId();
                this.oauthClientSecret = config.getOauthClientSecret();
                logger.log(Level.INFO, "Initialized OAuth 2.0 Authentication");
                break;
                
            default:
                logger.log(Level.WARNING, "Unknown auth type: " + authType + ", defaulting to basic");
                this.authType = "basic";
        }
    }
    
    /**
     * Get OAuth token, refreshing if necessary
     */
    private CompletableFuture<String> getOAuthToken() {
        // Check if token is still valid (with 5 minute buffer)
        if (oauthToken != null && System.currentTimeMillis() < (oauthTokenExpiry - 300000)) {
            return CompletableFuture.completedFuture(oauthToken);
        }
        
        // Request new token
        return CompletableFuture.supplyAsync(() -> {
            try {
                String requestBody = String.format(
                    "grant_type=client_credentials&client_id=%s&client_secret=%s",
                    oauthClientId, oauthClientSecret
                );
                
                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(oauthTokenUrl))
                        .header("Content-Type", "application/x-www-form-urlencoded")
                        .POST(HttpRequest.BodyPublishers.ofString(requestBody))
                        .build();
                
                HttpResponse<String> response = httpClient.send(request, 
                        HttpResponse.BodyHandlers.ofString());
                
                if (response.statusCode() == 200) {
                    JSONObject jsonResponse = new JSONObject(response.body());
                    oauthToken = jsonResponse.getString("access_token");
                    int expiresIn = jsonResponse.optInt("expires_in", 3600);
                    oauthTokenExpiry = System.currentTimeMillis() + (expiresIn * 1000L);
                    
                    logger.log(Level.INFO, "OAuth token obtained successfully");
                    return oauthToken;
                } else {
                    logger.log(Level.SEVERE, "Failed to obtain OAuth token. Status: " + 
                            response.statusCode());
                    throw new RuntimeException("OAuth token request failed");
                }
            } catch (Exception e) {
                logger.log(Level.SEVERE, "Error obtaining OAuth token", e);
                throw new RuntimeException("OAuth token request failed", e);
            }
        });
    }
    
    /**
     * Build HTTP request with appropriate authentication headers
     */
    private CompletableFuture<HttpRequest.Builder> buildAuthenticatedRequest(String url) {
        HttpRequest.Builder builder = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Accept", "application/json")
                .header("Content-Type", "application/json");
        
        // Add Maximo-specific headers
        if (maximoOrgId != null && !maximoOrgId.isEmpty()) {
            builder.header("x-public-uri", baseUrl);
        }
        
        if (authType.equals("oauth")) {
            return getOAuthToken().thenApply(token -> {
                builder.header("Authorization", "Bearer " + token);
                return builder;
            });
        } else {
            builder.header("Authorization", authHeader);
            return CompletableFuture.completedFuture(builder);
        }
    }
    
    /**
     * Perform GET request to Maximo API
     */
    public CompletableFuture<HttpResponse<String>> get(String path) {
        String url = baseUrl + path;
        logger.log(Level.INFO, "GET request to: " + url);
        
        return buildAuthenticatedRequest(url)
                .thenCompose(builder -> {
                    try {
                        HttpRequest request = builder.GET().build();
                        return httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString());
                    } catch (Exception e) {
                        logger.log(Level.SEVERE, "Error building GET request", e);
                        return CompletableFuture.failedFuture(e);
                    }
                });
    }
    
    /**
     * Perform POST request to Maximo API
     */
    public CompletableFuture<HttpResponse<String>> post(String path, String body) {
        String url = baseUrl + path;
        logger.log(Level.INFO, "POST request to: " + url);
        logger.log(Level.FINE, "Request body: " + body);
        
        return buildAuthenticatedRequest(url)
                .thenCompose(builder -> {
                    try {
                        HttpRequest request = builder
                                .POST(HttpRequest.BodyPublishers.ofString(body))
                                .build();
                        return httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString());
                    } catch (Exception e) {
                        logger.log(Level.SEVERE, "Error building POST request", e);
                        return CompletableFuture.failedFuture(e);
                    }
                });
    }
    
    /**
     * Perform PATCH request to Maximo API
     */
    public CompletableFuture<HttpResponse<String>> patch(String path, String body) {
        String url = baseUrl + path;
        logger.log(Level.INFO, "PATCH request to: " + url);
        logger.log(Level.FINE, "Request body: " + body);
        
        return buildAuthenticatedRequest(url)
                .thenCompose(builder -> {
                    try {
                        HttpRequest request = builder
                                .method("PATCH", HttpRequest.BodyPublishers.ofString(body))
                                .build();
                        return httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString());
                    } catch (Exception e) {
                        logger.log(Level.SEVERE, "Error building PATCH request", e);
                        return CompletableFuture.failedFuture(e);
                    }
                });
    }
    
    /**
     * Perform DELETE request to Maximo API
     */
    public CompletableFuture<HttpResponse<String>> delete(String path) {
        String url = baseUrl + path;
        logger.log(Level.INFO, "DELETE request to: " + url);
        
        return buildAuthenticatedRequest(url)
                .thenCompose(builder -> {
                    try {
                        HttpRequest request = builder.DELETE().build();
                        return httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString());
                    } catch (Exception e) {
                        logger.log(Level.SEVERE, "Error building DELETE request", e);
                        return CompletableFuture.failedFuture(e);
                    }
                });
    }
    
    /**
     * Test connection to Maximo
     */
    public CompletableFuture<Boolean> testConnection() {
        logger.log(Level.INFO, "Testing connection to Maximo");
        
        // Test with a simple query to the incident API
        String testPath = "/maximo/oslc/os/mxincident?oslc.select=ticketid&oslc.pageSize=1";
        
        return get(testPath)
                .thenApply(response -> {
                    boolean success = response.statusCode() >= 200 && response.statusCode() < 300;
                    if (success) {
                        logger.log(Level.INFO, "Connection test successful");
                    } else {
                        logger.log(Level.WARNING, "Connection test failed with status: " + 
                                response.statusCode());
                        logger.log(Level.WARNING, "Response: " + response.body());
                    }
                    return success;
                })
                .exceptionally(ex -> {
                    logger.log(Level.SEVERE, "Connection test failed with exception", ex);
                    return false;
                });
    }
    
    public String getMaximoOrgId() {
        return maximoOrgId;
    }
    
    public String getMaximoSiteId() {
        return maximoSiteId;
    }
}

// Made with Bob
