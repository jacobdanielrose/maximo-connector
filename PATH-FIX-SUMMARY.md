# Maximo Connector Path Fix Summary

## Problem Discovery

The connector was showing "Retrying" status with connection failures to Maximo.

## Initial Investigation

1. **First Assumption**: The duplicate `/maximo` in paths was causing 404 errors
   - URLs were like: `https://mas.../maximo/maximo/oslc/os/mxincident`
   - We removed the duplicate `/maximo` prefix

2. **After Removal**: Still got errors, but now we could see detailed logs:
   - GET request to: `https://mas.../oslc/os/mxincident?...`
   - **Result: HTTP 404 - Not Found**

## Root Cause

The Maximo REST API actually **REQUIRES** the `/maximo` prefix in the path. The correct URL structure is:
```
https://mas.manage.dev.apps.itz-tq25he.tzaas.techzone.ibm.com/maximo/oslc/os/mxincident
```

## Solution

Reverted all path changes to restore the `/maximo` prefix:

### Files Modified (Reverted):
1. **MaximoHttpClient.java** (line 305)
   - Restored: `/maximo/oslc/os/mxincident?...`

2. **MaximoIncidentActions.java** (lines 264, 314, 360)
   - Restored: `/maximo/oslc/os/mxincident` for create
   - Restored: `/maximo/oslc/os/mxincident/{id}` for update/close

3. **MaximoIncidentPoller.java** (line 134)
   - Restored: `/maximo/oslc/os/mxincident?...` for polling

## Next Steps

1. Rebuild Docker image with reverted changes
2. Push new image to quay.io with unique tag
3. Update deployment to use new image
4. Verify connection test succeeds
5. Check for any remaining SSL or authentication issues

## Lessons Learned

- The `/maximo` prefix is part of the Maximo REST API URL structure
- Always verify API paths with actual HTTP responses before making assumptions
- The 404 error was the key indicator that the path was incorrect