# HyperDX Ingress Testing Commands

## Quick Start

### 1. Full E2E Test (Automated)
```bash
# Complete setup with ingress controller + HyperDX (basic config)
./scripts/e2e-ingress-test.sh

# Test with example configurations
./scripts/e2e-ingress-test.sh --config examples/values-ingress-basic.yaml
./scripts/e2e-ingress-test.sh --config examples/values-ingress-otel.yaml
./scripts/e2e-ingress-test.sh --config examples/values-ingress-tls.yaml
./scripts/e2e-ingress-test.sh --config examples/values-with-secrets.yaml
./scripts/e2e-ingress-test.sh --config examples/values-production-like.yaml
./scripts/e2e-ingress-test.sh --config examples/values-minimal.yaml

# Test with published chart (latest version)
./scripts/e2e-ingress-test.sh --config examples/values-ingress-basic.yaml --chart-source published

# Test broken config (reproduces customer issue)
./scripts/e2e-ingress-test.sh --broken-config

# Cleanup only
./scripts/e2e-ingress-test.sh --skip-hyperdx --skip-ingress
```

### 2. Available Example Configurations

#### Basic Ingress (`examples/values-ingress-basic.yaml`)
- Simple ingress setup
- Minimal configuration for testing

#### OTEL Ingress (`examples/values-ingress-otel.yaml`)
- Exposes OTEL collector via ingress
- External telemetry data can be sent to cluster
- Endpoints: `/v1/traces`, `/v1/metrics`, `/v1/logs`

#### With Secrets (`examples/values-with-secrets.yaml`)
- Uses external Kubernetes secrets for connections/sources
- Example of production-like secret management
- Automatically creates example secrets

#### TLS/HTTPS (`examples/values-ingress-tls.yaml`)
- Configures ingress with TLS certificates
- Uses HTTPS URLs for frontend
- Includes cert-manager annotations

#### Production-like (`examples/values-production-like.yaml`)
- Resource limits and requests
- Multiple replicas for HA
- Node selectors and pod disruption budgets
- Larger persistent volumes

#### Minimal (`examples/values-minimal.yaml`)
- Reduced resource requirements
- Single replicas
- Smaller persistent volumes
- Ideal for development environments

### 2. Manual Step-by-Step Commands

#### Prerequisites
```bash
# Ensure you're in the right context
kubectl config current-context

# Add required helm repos
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

#### Install Ingress Controller
```bash
# Install nginx ingress controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --wait --timeout=600s

# Wait for external IP
kubectl get service -n ingress-nginx ingress-nginx-controller --watch
```

#### Get Domain for Testing
```bash
# Get the load balancer IP
INGRESS_IP=$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# For AWS (gets hostname first, then resolves)
INGRESS_HOSTNAME=$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
INGRESS_IP=$(dig +short $INGRESS_HOSTNAME | head -1)

# Create test domain using nip.io
TEST_DOMAIN="hyperdx-test.${INGRESS_IP}.nip.io"
echo "Test domain: $TEST_DOMAIN"
```

#### Install HyperDX (CORRECT Config)
```bash
# Create namespace
kubectl create namespace hyperdx-ingress-test

# Install with correct configuration
helm install hyperdx-test ./charts/hdx-oss-v2 \
  --namespace hyperdx-ingress-test \
  --set hyperdx.appUrl="http://${TEST_DOMAIN}" \
  --set hyperdx.frontendUrl="http://${TEST_DOMAIN}" \
  --set hyperdx.ingress.enabled=true \
  --set hyperdx.ingress.ingressClassName=nginx \
  --set hyperdx.ingress.host="${TEST_DOMAIN}" \
  --set global.storageClassName=gp2 \
  --set mongodb.persistence.dataSize=1Gi \
  --set clickhouse.persistence.dataSize=1Gi \
  --wait --timeout=600s
```

#### Install HyperDX (BROKEN Config - for testing customer issue)
```bash
# Install with broken configuration (reproduces customer issue)
helm install hyperdx-test ./charts/hdx-oss-v2 \
  --namespace hyperdx-ingress-test \
  --set hyperdx.appUrl="http://${TEST_DOMAIN}" \
  --set hyperdx.frontendUrl="http://${TEST_DOMAIN}:3000" \
  --set hyperdx.ingress.enabled=true \
  --set hyperdx.ingress.ingressClassName=nginx \
  --set hyperdx.ingress.host="${TEST_DOMAIN}" \
  --set global.storageClassName=gp2 \
  --set mongodb.persistence.dataSize=1Gi \
  --set clickhouse.persistence.dataSize=1Gi \
  --wait --timeout=600s
```

#### Fix Broken Config
```bash
# Upgrade to fix the broken config
helm upgrade hyperdx-test ./charts/hdx-oss-v2 \
  --namespace hyperdx-ingress-test \
  --set hyperdx.frontendUrl="http://${TEST_DOMAIN}" \
  --reuse-values
```

## Verification Commands

### Check Status
```bash
# Check all pods
kubectl get pods -n hyperdx-ingress-test

# Check ingress
kubectl get ingress -n hyperdx-ingress-test

# Check configuration
kubectl get configmap hyperdx-test-hdx-oss-v2-app-config -n hyperdx-ingress-test -o yaml | grep FRONTEND_URL
```

### Test Access
```bash
# Test URL accessibility
curl -I http://${TEST_DOMAIN}

# Open in browser
open http://${TEST_DOMAIN}

# Test OTEL endpoints (if using values-ingress-otel.yaml)
OTEL_DOMAIN="otel.${INGRESS_IP}.nip.io"
curl -X POST http://${OTEL_DOMAIN}/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"test-service"}}]},"scopeSpans":[{"spans":[{"traceId":"12345678901234567890123456789012","spanId":"1234567890123456","name":"test-span","kind":1,"startTimeUnixNano":"1640995200000000000","endTimeUnixNano":"1640995201000000000"}]}]}]}'

# Test metrics endpoint
curl -X POST http://${OTEL_DOMAIN}/v1/metrics \
  -H "Content-Type: application/json" \
  -d '{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"test-service"}}]},"scopeMetrics":[{"metrics":[{"name":"test_metric","unit":"1","gauge":{"dataPoints":[{"timeUnixNano":"1640995200000000000","asDouble":42.0}]}}]}]}]}'
```

### Debug
```bash
# Check app logs
kubectl logs -f deployment/hyperdx-test-hdx-oss-v2-app -n hyperdx-ingress-test

# Check ingress controller logs
kubectl logs -f deployment/ingress-nginx-controller -n ingress-nginx

# Describe problematic pods
kubectl describe pod <pod-name> -n hyperdx-ingress-test
```

## Cleanup Commands

### Clean HyperDX Only
```bash
# Uninstall HyperDX
helm uninstall hyperdx-test -n hyperdx-ingress-test

# Delete namespace
kubectl delete namespace hyperdx-ingress-test
```

### Full Cleanup
```bash
# Uninstall everything
helm uninstall hyperdx-test -n hyperdx-ingress-test || true
helm uninstall ingress-nginx -n ingress-nginx || true

# Delete namespaces
kubectl delete namespace hyperdx-ingress-test || true
kubectl delete namespace ingress-nginx || true
```

## CI/CD Usage

### In GitHub Actions / CI Pipeline
```yaml
steps:
  - name: Setup E2E Test Environment
    run: |
      # Install ingress and HyperDX
      ./scripts/e2e-ingress-test.sh --skip-test
      
  - name: Run Tests
    run: |
      # Your E2E tests here
      TEST_DOMAIN=$(kubectl get ingress -n hyperdx-ingress-test -o jsonpath='{.items[0].spec.rules[0].host}')
      curl -f http://${TEST_DOMAIN} || exit 1
      
  - name: Cleanup
    if: always()
    run: |
      helm uninstall hyperdx-test -n hyperdx-ingress-test || true
      kubectl delete namespace hyperdx-ingress-test || true
```

### Local Development
```bash
# Quick test cycle
./scripts/e2e-ingress-test.sh
# ... make changes ...
helm upgrade hyperdx-test ./charts/hdx-oss-v2 --namespace hyperdx-ingress-test --reuse-values
# ... test again ...
```

## Environment Variables

- `NAMESPACE`: Target namespace (default: hyperdx-ingress-test)
- `RELEASE_NAME`: Helm release name (default: hyperdx-test)
- `STORAGE_CLASS`: Storage class (default: gp2)
- `TIMEOUT`: Timeout in seconds (default: 600)

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending**: Check storage class and PVC status
2. **Ingress not getting IP**: Wait longer, check cloud provider load balancer limits
3. **Domain not resolving**: Verify nip.io is accessible, try different DNS server
4. **App not loading**: Check frontendUrl in configmap, verify it matches access URL

### Storage Class Issues
```bash
# Check available storage classes
kubectl get storageclass

# Use different storage class
helm install ... --set global.storageClassName=local-path
```