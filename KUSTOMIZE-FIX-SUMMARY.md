# Kustomize Validation Fixes - Summary

## Issues Found and Fixed

### Issue 1: Wrong Volume Index in Patch
**Problem**: The kustomization patch was trying to replace the secret name at volume index 2, but the `grpc-bridge-service-binding` volume is actually at index 3.

**Location**: `bundle-artifacts/connector/kustomization.yaml` line 38

**Fix**: Changed from:
```yaml
path: /spec/template/spec/volumes/2/projected/sources/1/secret/name
```
To:
```yaml
path: /spec/template/spec/volumes/3/projected/sources/1/secret/name
```

**Commit**: `60fdb9f` - "Fix kustomization patch: correct volume index from 2 to 3"

---

### Issue 2: Invalid Kustomize Vars
**Problem**: The kustomization was using deprecated `vars` feature to extract `SERVICE_NAME` and `SERVICE_NAMESPACE` from the service resource. The `metadata.namespace` field doesn't exist in the service.yaml file, causing the error:
```
field specified in var '{SERVICE_NAMESPACE Service.v1.[noGrp] {metadata.namespace}}' not found in corresponding resource
```

**Location**: 
- `bundle-artifacts/connector/kustomization.yaml` lines 19-33
- `bundle-artifacts/connector/servicemonitor.yaml` line 13

**Fix**: 
1. Removed the entire `vars` section from kustomization.yaml
2. Hardcoded the serverName in servicemonitor.yaml:
   ```yaml
   serverName: "java-grpc-conn-template.ibm-aiops.svc"
   ```

**Commit**: Latest - "Fix kustomize vars: remove unused SERVICE_NAME/NAMESPACE vars and hardcode serverName"

---

## Validation

The kustomize build now completes successfully:
```bash
cd bundle-artifacts/connector && kubectl kustomize .
# SUCCESS: Kustomize build completed
# 257 lines of output
```

---

## Next Steps

1. **Wait for bundle to process** (currently in progress)
   - The bundle manifest has been redeployed with the fixes
   - Waiting 60 seconds for it to fetch the updated repo and process

2. **Check deployment creation**
   ```bash
   oc get deployment ticket-template -n ibm-aiops
   ```

3. **If deployment exists, check pods**
   ```bash
   oc get pods -n ibm-aiops -l app=ticket-template
   ```

4. **If pods are running, check logs for authentication**
   ```bash
   oc logs -n ibm-aiops -l app=ticket-template --tail=50
   ```

---

## Expected Outcome

With these fixes:
- ✅ Kustomize validation should pass
- ✅ Bundle manifest should reach "Configured" status
- ✅ Deployment should be created
- ✅ Pods should start
- ⏳ Pods should authenticate with connector bridge (no more UNAUTHENTICATED errors)

---

## Volume Index Reference (deployment.yaml)

For future reference, the volumes array in deployment.yaml:
- `volumes[0]` = server-certs-raw (line 164)
- `volumes[1]` = server-certs (line 168)
- `volumes[2]` = config-overrides (line 170)
- `volumes[3]` = grpc-bridge-service-binding (line 172) ← **This is the one we patch**
- `volumes[4]` = search (line 202)