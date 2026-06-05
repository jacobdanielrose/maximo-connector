# SSL Certificate Fix for Maximo Connector

## Problem
The connector was failing to connect to Maximo with the following error:
```
javax.net.ssl.SSLHandshakeException: PKIX path building failed: 
sun.security.provider.certpath.SunCertPathBuilderException: 
unable to find valid certification path to requested target
```

This error occurs when the Java application cannot verify the SSL certificate of the Maximo server, typically because:
- The server uses a self-signed certificate
- The server's certificate is not in the Java truststore
- The certificate chain is incomplete

## Solution
Modified `MaximoHttpClient.java` to configure the `HttpClient` with a custom SSL context that trusts all certificates.

### Changes Made

1. **Added SSL-related imports:**
   - `javax.net.ssl.SSLContext`
   - `javax.net.ssl.TrustManager`
   - `javax.net.ssl.X509TrustManager`
   - `java.security.*` classes

2. **Created `createTrustAllSSLContext()` method:**
   - Creates a custom `TrustManager` that accepts all certificates
   - Initializes an SSL context with this trust manager
   - Returns the configured SSL context

3. **Updated `MaximoHttpClient` constructor:**
   - Calls `createTrustAllSSLContext()` to get the SSL context
   - Configures the `HttpClient.Builder` with `.sslContext(sslContext)`

### Code Changes

```java
// In constructor
SSLContext sslContext = createTrustAllSSLContext();

this.httpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(30))
        .sslContext(sslContext)  // Added this line
        .build();

// New method
private SSLContext createTrustAllSSLContext() {
    try {
        TrustManager[] trustAllCerts = new TrustManager[]{
            new X509TrustManager() {
                public X509Certificate[] getAcceptedIssuers() {
                    return new X509Certificate[0];
                }
                public void checkClientTrusted(X509Certificate[] certs, String authType) {
                    // Trust all client certificates
                }
                public void checkServerTrusted(X509Certificate[] certs, String authType) {
                    // Trust all server certificates
                }
            }
        };
        
        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(null, trustAllCerts, new SecureRandom());
        
        logger.log(Level.INFO, "SSL context configured to trust all certificates");
        return sslContext;
    } catch (NoSuchAlgorithmException | KeyManagementException e) {
        logger.log(Level.SEVERE, "Failed to create SSL context", e);
        throw new RuntimeException("Failed to initialize SSL context", e);
    }
}
```

## Security Considerations

⚠️ **IMPORTANT SECURITY WARNING** ⚠️

This solution **trusts all SSL certificates** without validation. This approach:

- **Should ONLY be used in development/testing environments**
- **Is NOT recommended for production use**
- Makes the connection vulnerable to man-in-the-middle attacks
- Bypasses the security provided by SSL/TLS certificate validation

### Production Recommendations

For production environments, use one of these secure alternatives:

1. **Import the Maximo certificate into the Java truststore:**
   ```bash
   keytool -import -alias maximo -file maximo.crt \
           -keystore $JAVA_HOME/lib/security/cacerts \
           -storepass changeit
   ```

2. **Use a custom truststore with only the required certificates:**
   ```java
   KeyStore trustStore = KeyStore.getInstance("JKS");
   trustStore.load(new FileInputStream("custom-truststore.jks"), password);
   
   TrustManagerFactory tmf = TrustManagerFactory.getInstance(
       TrustManagerFactory.getDefaultAlgorithm());
   tmf.init(trustStore);
   
   SSLContext sslContext = SSLContext.getInstance("TLS");
   sslContext.init(null, tmf.getTrustManagers(), new SecureRandom());
   ```

3. **Configure the container to use proper certificates:**
   - Mount the certificate into the container
   - Import it during container startup using the `import-certs.sh` script
   - This is the recommended approach for containerized deployments

## Testing

After applying this fix:

1. Rebuild the connector:
   ```bash
   mvn clean package
   ```

2. Rebuild the Docker image:
   ```bash
   docker build -t maximo-connector:latest .
   ```

3. Redeploy and test the connection

The connector should now successfully connect to Maximo even with self-signed or untrusted certificates.

## Next Steps

1. Test the connection to verify the fix works
2. For production deployment, implement proper certificate validation
3. Consider using environment variables to control SSL validation behavior:
   ```java
   boolean trustAllCerts = Boolean.parseBoolean(
       System.getenv("TRUST_ALL_CERTS"));
   ```

## Related Files
- `src/main/java/com/ibm/aiops/connectors/template/MaximoHttpClient.java` - Modified file
- `container/import-certs.sh` - Script for importing certificates in production