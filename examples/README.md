# HyperDX Example Configurations

This directory contains example configurations for testing different HyperDX scenarios with ingress.

## Available Examples

### 1. `values-ingress-basic.yaml`
**Basic ingress configuration**
- Simple ingress setup
- Minimal configuration for testing
- Good starting point for new deployments

**Usage:**
```bash
./scripts/e2e-ingress-test.sh --config examples/values-ingress-basic.yaml
```

### 2. `values-ingress-otel.yaml`
**OTEL collector exposure via ingress**
- Exposes OTEL collector endpoints externally
- Allows sending telemetry data from outside the cluster
- Creates additional ingress for OTEL endpoints

**Endpoints created:**
- `http://otel.{IP}.nip.io/v1/traces`
- `http://otel.{IP}.nip.io/v1/metrics`
- `http://otel.{IP}.nip.io/v1/logs`

**Usage:**
```bash
./scripts/e2e-ingress-test.sh --config examples/values-ingress-otel.yaml

# Test sending telemetry data
OTEL_DOMAIN="otel.$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}').nip.io"
curl -X POST http://${OTEL_DOMAIN}/v1/traces -H "Content-Type: application/json" -d '{...}'
```

### 3. `values-with-secrets.yaml`
**External secrets configuration**
- Uses Kubernetes secrets for connections and sources
- Example of production-like secret management
- Automatically creates example secrets when used

**Usage:**
```bash
./scripts/e2e-ingress-test.sh --config examples/values-with-secrets.yaml

# Or create secrets manually first
./scripts/e2e-ingress-test.sh --config examples/values-with-secrets.yaml --create-secrets
```

### 4. `values-ingress-tls.yaml`
**HTTPS/TLS configuration**
- Configures ingress with TLS certificates
- Includes cert-manager annotations for automatic SSL
- Uses HTTPS URLs for frontend

**Usage:**
```bash
./scripts/e2e-ingress-test.sh --config examples/values-ingress-tls.yaml
# Note: Requires cert-manager for automatic certificate generation
```

### 5. `values-production-like.yaml`
**Production-like configuration**
- Resource limits and requests
- Multiple replicas for high availability
- Node selectors for workload placement
- Pod disruption budgets
- Larger persistent volumes

**Usage:**
```bash
./scripts/e2e-ingress-test.sh --config examples/values-production-like.yaml
```

### 6. `values-minimal.yaml`
**Minimal resource configuration**
- Reduced memory and CPU requests/limits
- Smaller persistent volumes
- Single replicas
- Ideal for development or resource-constrained environments

**Usage:**
```bash
./scripts/e2e-ingress-test.sh --config examples/values-minimal.yaml
```

## Creating Custom Configurations

To create your own configuration:

1. **Copy an existing example:**
   ```bash
   cp examples/values-ingress-basic.yaml examples/my-custom-config.yaml
   ```

2. **Use placeholders for dynamic values:**
   - `PLACEHOLDER_DOMAIN` - Will be replaced with `http://hyperdx-test.{IP}.nip.io`
   - `PLACEHOLDER_DOMAIN_HTTPS` - Will be replaced with `https://hyperdx-test.{IP}.nip.io`
   - `PLACEHOLDER_OTEL_DOMAIN` - Will be replaced with `otel.{IP}.nip.io`
   - `PLACEHOLDER_DOMAIN_WITH_PORT` - For broken configs, includes `:3000`

3. **Test your configuration:**
   ```bash
   ./scripts/e2e-ingress-test.sh --config examples/my-custom-config.yaml
   ```

## Testing with Published vs Local Charts

### Local Chart (Default)
Tests your local changes and modifications:
```bash
./scripts/e2e-ingress-test.sh --config examples/values-ingress-basic.yaml
# Uses ./charts/hdx-oss-v2
```

### Published Chart
Tests the latest published version from the Helm repository:
```bash
./scripts/e2e-ingress-test.sh --config examples/values-ingress-basic.yaml --chart-source published
# Uses hyperdx/hdx-oss-v2 from repository
```

This is useful for:
- **Regression testing** - Ensure your changes work with the published version
- **Customer issue reproduction** - Test with the same chart version customers use
- **Release validation** - Verify published charts work in different configurations

## Template Processing

The E2E script automatically processes placeholders:

```yaml
# Before processing
hyperdx:
  appUrl: "PLACEHOLDER_DOMAIN"
  frontendUrl: "PLACEHOLDER_DOMAIN"
  ingress:
    host: "PLACEHOLDER_DOMAIN"

# After processing (example)
hyperdx:
  appUrl: "http://hyperdx-test.18.216.238.214.nip.io"
  frontendUrl: "http://hyperdx-test.18.216.238.214.nip.io"
  ingress:
    host: "hyperdx-test.18.216.238.214.nip.io"
```

## Secrets Example

When using `values-with-secrets.yaml`, the script creates this secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: hyperdx-config-secret
type: Opaque
data:
  connections.json: # Base64 encoded connections config
  sources.json:     # Base64 encoded sources config
```

You can customize the secret contents by modifying the `create_example_secrets()` function in the E2E script.

## Best Practices

1. **Start with basic config** - Use `values-ingress-basic.yaml` first
2. **Test broken config** - Verify the fix works with `values-broken-config.yaml`
3. **Use secrets for production** - Follow `values-with-secrets.yaml` pattern
4. **Expose OTEL carefully** - Only use `values-ingress-otel.yaml` when needed
5. **Clean up between tests** - The script handles cleanup automatically