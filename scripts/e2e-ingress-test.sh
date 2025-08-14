#!/bin/bash
set -e

# End-to-End Ingress Test Script for HyperDX
# This script can be used for local testing and CI/CD pipelines

# Configuration
NAMESPACE=${NAMESPACE:-hyperdx-ingress-test}
RELEASE_NAME=${RELEASE_NAME:-hyperdx-test}
INGRESS_NAMESPACE=${INGRESS_NAMESPACE:-ingress-nginx}
STORAGE_CLASS=${STORAGE_CLASS:-gp2}
TIMEOUT=${TIMEOUT:-600}
CHART_SOURCE=${CHART_SOURCE:-local}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}
    
    log "Waiting for pods with label '$label' in namespace '$namespace' to be ready..."
    if kubectl wait --for=condition=Ready pods -l "$label" --timeout=${timeout}s -n "$namespace" >/dev/null 2>&1; then
        success "Pods are ready"
    else
        error "Pods failed to become ready within ${timeout}s"
        kubectl get pods -n "$namespace" -l "$label"
        return 1
    fi
}

# Function to get ingress IP
get_ingress_ip() {
    local max_attempts=30
    local attempt=1
    
    log "Getting ingress controller IP..."
    
    while [ $attempt -le $max_attempts ]; do
        # Try to get IP first (for some cloud providers)
        INGRESS_IP=$(kubectl get service -n $INGRESS_NAMESPACE ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [ -n "$INGRESS_IP" ] && [ "$INGRESS_IP" != "null" ]; then
            success "Got ingress IP: $INGRESS_IP"
            return 0
        fi
        
        # Try hostname (for AWS ELB)
        INGRESS_HOSTNAME=$(kubectl get service -n $INGRESS_NAMESPACE ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        if [ -n "$INGRESS_HOSTNAME" ] && [ "$INGRESS_HOSTNAME" != "null" ]; then
            log "Got ingress hostname: $INGRESS_HOSTNAME, resolving to IP..."
            INGRESS_IP=$(dig +short $INGRESS_HOSTNAME | head -1)
            if [ -n "$INGRESS_IP" ]; then
                success "Resolved to IP: $INGRESS_IP"
                return 0
            fi
        fi
        
        log "Attempt $attempt/$max_attempts: Waiting for ingress IP..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    error "Failed to get ingress IP after $max_attempts attempts"
    return 1
}

# Function to test URL
test_url() {
    local url=$1
    local expected_code=${2:-200}
    local max_attempts=10
    local attempt=1
    
    log "Testing URL: $url"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f -o /dev/null "$url"; then
            success "URL is accessible: $url"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts: URL not ready yet..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    warn "URL may not be ready: $url"
    return 1
}

# Function to create example secrets
create_example_secrets() {
    log "Creating example secrets for HyperDX..."
    
    # Create connections.json
    cat > /tmp/connections.json <<EOF
[
  {
    "name": "Local ClickHouse",
    "host": "http://${RELEASE_NAME}-hdx-oss-v2-clickhouse:8123",
    "port": 8123,
    "username": "app",
    "password": "hyperdx"
  },
  {
    "name": "External ClickHouse",
    "host": "https://external-clickhouse.example.com",
    "port": 8443,
    "username": "external_user",
    "password": "external_password"
  }
]
EOF

    # Create sources.json
    cat > /tmp/sources.json <<EOF
[
  {
    "from": {
      "databaseName": "default",
      "tableName": "otel_logs"
    },
    "to": {
      "sourceId": "Logs"
    }
  },
  {
    "from": {
      "databaseName": "default",
      "tableName": "otel_traces"
    },
    "to": {
      "sourceId": "Traces",
      "traceSourceId": "Traces",
      "metricSourceId": "Metrics"
    }
  }
]
EOF

    # Create the secret
    kubectl create secret generic hyperdx-config-secret \
        --from-file=connections.json=/tmp/connections.json \
        --from-file=sources.json=/tmp/sources.json \
        -n $NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Cleanup temp files
    rm -f /tmp/connections.json /tmp/sources.json
    
    success "Example secrets created"
}

# Function to process config file
process_config_file() {
    local config_file=$1
    local processed_file="/tmp/processed-values.yaml"
    
    if [ ! -f "$config_file" ]; then
        error "Config file not found: $config_file"
        exit 1
    fi
    
    log "Processing config file: $config_file"
    
    # Copy and process the config file
    cp "$config_file" "$processed_file"
    
    # Replace placeholders
    sed -i.bak "s|PLACEHOLDER_DOMAIN|http://${TEST_DOMAIN}|g" "$processed_file"
    sed -i.bak "s|PLACEHOLDER_DOMAIN_HTTPS|https://${TEST_DOMAIN}|g" "$processed_file"
    sed -i.bak "s|PLACEHOLDER_OTEL_DOMAIN|otel.${INGRESS_IP}.nip.io|g" "$processed_file"
    
    # Handle broken config
    if [ "$BROKEN_CONFIG" = true ]; then
        sed -i.bak "s|PLACEHOLDER_DOMAIN_WITH_PORT|http://${TEST_DOMAIN}:3000|g" "$processed_file"
        warn "Processing as BROKEN config - frontendUrl will include port"
    else
        sed -i.bak "s|PLACEHOLDER_DOMAIN_WITH_PORT|http://${TEST_DOMAIN}|g" "$processed_file"
    fi
    
    # Clean up backup files
    rm -f "$processed_file.bak"
    
    echo "$processed_file"
}

# Parse command line arguments
INSTALL_INGRESS=true
INSTALL_HYPERDX=true
CLEANUP_FIRST=true
TEST_URL=true
BROKEN_CONFIG=false
CONFIG_FILE=""
CREATE_SECRETS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-ingress)
            INSTALL_INGRESS=false
            shift
            ;;
        --skip-hyperdx)
            INSTALL_HYPERDX=false
            shift
            ;;
        --no-cleanup)
            CLEANUP_FIRST=false
            shift
            ;;
        --skip-test)
            TEST_URL=false
            shift
            ;;
        --broken-config)
            BROKEN_CONFIG=true
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --create-secrets)
            CREATE_SECRETS=true
            shift
            ;;
        --chart-source)
            CHART_SOURCE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-ingress     Skip ingress controller installation"
            echo "  --skip-hyperdx     Skip HyperDX installation"
            echo "  --no-cleanup       Don't cleanup existing resources first"
            echo "  --skip-test        Skip URL testing"
            echo "  --broken-config    Deploy with broken frontendUrl (for testing the issue)"
            echo "  --config FILE      Use custom values file (examples: examples/values-*.yaml)"
            echo "  --create-secrets   Create example secrets for testing"
            echo "  --chart-source SRC Chart source: 'local' (default) or 'published'"
            echo "  --help             Show this help message"
            echo ""
            echo "Available example configs:"
            echo "  examples/values-ingress-basic.yaml     - Basic ingress setup"
            echo "  examples/values-ingress-otel.yaml      - Ingress + OTEL collector exposure"
            echo "  examples/values-ingress-tls.yaml       - Ingress with TLS/HTTPS"
            echo "  examples/values-with-secrets.yaml      - Using external secrets"
            echo "  examples/values-production-like.yaml   - Production configuration"
            echo "  examples/values-minimal.yaml           - Minimal resource usage"
            echo ""
            echo "Chart sources:"
            echo "  local      - Use local chart (./charts/hdx-oss-v2)"
            echo "  published  - Use latest published chart from repository"
            echo ""
            echo "Environment variables:"
            echo "  NAMESPACE          Target namespace (default: hyperdx-ingress-test)"
            echo "  RELEASE_NAME       Helm release name (default: hyperdx-test)"
            echo "  STORAGE_CLASS      Storage class (default: gp2)"
            echo "  TIMEOUT            Timeout in seconds (default: 600)"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
log "Checking prerequisites..."
check_command kubectl
check_command helm
check_command dig
check_command curl

# Check kubectl context
CURRENT_CONTEXT=$(kubectl config current-context)
log "Using kubectl context: $CURRENT_CONTEXT"

# Cleanup existing resources if requested
if [ "$CLEANUP_FIRST" = true ]; then
    log "Cleaning up existing resources..."
    
    # Uninstall HyperDX if exists
    if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
        log "Uninstalling existing HyperDX release..."
        helm uninstall $RELEASE_NAME -n $NAMESPACE || true
    fi
    
    # Delete namespace if exists
    if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        log "Deleting namespace $NAMESPACE..."
        kubectl delete namespace $NAMESPACE || true
    fi
    
    # Uninstall ingress controller if exists and we're going to reinstall it
    if [ "$INSTALL_INGRESS" = true ] && helm list -n $INGRESS_NAMESPACE | grep -q ingress-nginx; then
        log "Uninstalling existing ingress controller..."
        helm uninstall ingress-nginx -n $INGRESS_NAMESPACE || true
        kubectl delete namespace $INGRESS_NAMESPACE || true
    fi
    
    success "Cleanup completed"
fi

# Install ingress controller
if [ "$INSTALL_INGRESS" = true ]; then
    log "Installing nginx ingress controller..."
    
    # Add helm repo
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    
    # Install ingress controller
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace $INGRESS_NAMESPACE \
        --create-namespace \
        --set controller.service.type=LoadBalancer \
        --wait --timeout=${TIMEOUT}s
    
    success "Ingress controller installed"
    
    # Wait for ingress to be ready
    wait_for_pods $INGRESS_NAMESPACE "app.kubernetes.io/name=ingress-nginx"
    
    # Get ingress IP
    get_ingress_ip
    
    if [ -z "$INGRESS_IP" ]; then
        error "Failed to get ingress IP"
        exit 1
    fi
else
    log "Skipping ingress installation, getting existing ingress IP..."
    get_ingress_ip
fi

# Create test domain
TEST_DOMAIN="hyperdx-test.${INGRESS_IP}.nip.io"
log "Using test domain: $TEST_DOMAIN"

# Install HyperDX
if [ "$INSTALL_HYPERDX" = true ]; then
    log "Installing HyperDX..."
    
    # Create namespace
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Create secrets if needed
    if [ "$CREATE_SECRETS" = true ] || ([ -n "$CONFIG_FILE" ] && grep -q "useExistingConfigSecret.*true" "$CONFIG_FILE"); then
        create_example_secrets
    fi
    
    # Prepare helm install command based on chart source
    if [ "$CHART_SOURCE" = "published" ]; then
        # Add HyperDX helm repo if not already added
        if ! helm repo list | grep -q hyperdx; then
            log "Adding HyperDX helm repository..."
            helm repo add hyperdx https://hyperdxio.github.io/helm-charts
            helm repo update
        fi
        HELM_CMD="helm install $RELEASE_NAME hyperdx/hdx-oss-v2 --namespace $NAMESPACE"
        log "Using published chart from repository"
    else
        HELM_CMD="helm install $RELEASE_NAME ./charts/hdx-oss-v2 --namespace $NAMESPACE"
        log "Using local chart"
    fi
    
    # Use config file or default values
    if [ -n "$CONFIG_FILE" ]; then
        PROCESSED_CONFIG=$(process_config_file "$CONFIG_FILE")
        HELM_CMD="$HELM_CMD --values $PROCESSED_CONFIG"
        log "Using config file: $CONFIG_FILE"
    else
        # Default inline configuration
        if [ "$BROKEN_CONFIG" = true ]; then
            FRONTEND_URL="http://${TEST_DOMAIN}:3000"
            warn "Using BROKEN config: frontendUrl includes port (reproduces customer issue)"
        else
            FRONTEND_URL="http://${TEST_DOMAIN}"
            log "Using CORRECT config: frontendUrl matches ingress host"
        fi
        
        HELM_CMD="$HELM_CMD \
            --set hyperdx.appUrl=\"http://${TEST_DOMAIN}\" \
            --set hyperdx.frontendUrl=\"$FRONTEND_URL\" \
            --set hyperdx.ingress.enabled=true \
            --set hyperdx.ingress.ingressClassName=nginx \
            --set hyperdx.ingress.host=\"$TEST_DOMAIN\""
    fi
    
    # Add common settings
    HELM_CMD="$HELM_CMD \
        --set global.storageClassName=$STORAGE_CLASS \
        --set mongodb.persistence.dataSize=1Gi \
        --set clickhouse.persistence.dataSize=1Gi \
        --wait --timeout=${TIMEOUT}s"
    
    # Execute the helm command
    log "Executing: $HELM_CMD"
    eval $HELM_CMD
    
    success "HyperDX installed"
    
    # Wait for all pods to be ready
    wait_for_pods $NAMESPACE "app.kubernetes.io/instance=$RELEASE_NAME"
fi

# Test the deployment
if [ "$TEST_URL" = true ]; then
    log "Testing deployment..."
    
    # Check ingress
    kubectl get ingress -n $NAMESPACE
    
    # Test main URL
    test_url "http://${TEST_DOMAIN}"
    
    # Test OTEL endpoints if they exist
    OTEL_DOMAIN="otel.${INGRESS_IP}.nip.io"
    if kubectl get ingress -n $NAMESPACE | grep -q otel; then
        log "Testing OTEL collector endpoints..."
        success "OTEL collector available at: http://${OTEL_DOMAIN}"
        log "  - Traces: http://${OTEL_DOMAIN}/v1/traces"
        log "  - Metrics: http://${OTEL_DOMAIN}/v1/metrics" 
        log "  - Logs: http://${OTEL_DOMAIN}/v1/logs"
        
        # Test OTEL endpoint accessibility
        if curl -s -f -o /dev/null "http://${OTEL_DOMAIN}"; then
            success "OTEL endpoint is accessible"
        else
            warn "OTEL endpoint may not be ready yet"
        fi
    fi
    
    # Show config
    log "Checking configuration..."
    kubectl get configmap ${RELEASE_NAME}-hdx-oss-v2-app-config -n $NAMESPACE -o yaml | grep FRONTEND_URL
    
    # Show secrets if they exist
    if kubectl get secret hyperdx-config-secret -n $NAMESPACE >/dev/null 2>&1; then
        log "Found hyperdx-config-secret:"
        kubectl get secret hyperdx-config-secret -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'keys[]'
    fi
fi

# Final summary
echo ""
log "🎉 Deployment completed successfully!"
echo ""
success "Access URL: http://${TEST_DOMAIN}"
success "Namespace: $NAMESPACE"
success "Release: $RELEASE_NAME"

if [ -n "$CONFIG_FILE" ]; then
    success "Configuration: $CONFIG_FILE"
    if echo "$CONFIG_FILE" | grep -q "broken-config"; then
        warn "BROKEN CONFIG: This deployment reproduces the customer issue"
        warn "Expected: 304 errors or asset loading issues"
    elif echo "$CONFIG_FILE" | grep -q "otel"; then
        success "OTEL CONFIG: OTEL collector exposed at http://otel.${INGRESS_IP}.nip.io"
    elif echo "$CONFIG_FILE" | grep -q "secrets"; then
        success "SECRETS CONFIG: Using external secrets for connections/sources"
    fi
elif [ "$BROKEN_CONFIG" = true ]; then
    warn "BROKEN CONFIG: This deployment reproduces the customer issue"
    warn "Frontend URL includes port (causes 304 errors)"
else
    success "CORRECT CONFIG: This deployment should work properly"
fi

# Show OTEL endpoints if available
if kubectl get ingress -n $NAMESPACE | grep -q otel; then
    echo ""
    success "📡 OTEL Collector Endpoints:"
    echo "  - Traces:  http://otel.${INGRESS_IP}.nip.io/v1/traces"
    echo "  - Metrics: http://otel.${INGRESS_IP}.nip.io/v1/metrics"
    echo "  - Logs:    http://otel.${INGRESS_IP}.nip.io/v1/logs"
fi

# Show secrets if available
if kubectl get secret hyperdx-config-secret -n $NAMESPACE >/dev/null 2>&1; then
    echo ""
    success "🔐 External secrets configured"
fi

echo ""
log "Useful commands:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl get ingress -n $NAMESPACE"
echo "  kubectl logs -f deployment/${RELEASE_NAME}-hdx-oss-v2-app -n $NAMESPACE"
echo "  helm get values $RELEASE_NAME -n $NAMESPACE"
echo "  helm uninstall $RELEASE_NAME -n $NAMESPACE"
echo "  kubectl delete namespace $NAMESPACE"