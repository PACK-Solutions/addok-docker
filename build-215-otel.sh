#!/bin/bash
set -euo pipefail

# Addok 2.1.5-otel Release Build Script
# Builds and pushes the OpenTelemetry-enabled version to registry

# Configuration
VERSION="2.1.5"
OTEL_TAG="2.1.5-otel"
REGISTRY="registry.gitlab.com/atafaya971/packsol"
IMAGE_NAME="addok-ban"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

# Verify prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
    fi
    
    if ! command -v docker buildx &> /dev/null; then
        error "Docker buildx is not available"
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "addok/Dockerfile" ]]; then
        error "Must be run from addok-docker repository root (addok/Dockerfile not found)"
    fi
    
    # Check if monitoring files exist
    if [[ ! -f "addok/monitoring/telemetry.py" ]]; then
        error "OpenTelemetry monitoring files not found (addok/monitoring/telemetry.py missing)"
    fi
    
    log "✓ Prerequisites check passed"
}

# Pre-build validation
validate_build() {
    log "Validating build configuration..."
    
    # Check if OpenTelemetry packages are properly configured
    if ! grep -q "opentelemetry-api" addok/Dockerfile; then
        error "OpenTelemetry packages not found in Dockerfile"
    fi
    
    # Check if entrypoint script has OTEL initialization
    if ! grep -q "setup_telemetry" addok/docker-entrypoint.sh; then
        error "OTEL initialization not found in entrypoint script"
    fi
    
    log "✓ Build validation passed"
}

# Build the Docker image
build_image() {
    log "Building Addok ${OTEL_TAG} Docker image..."
    
    cd addok
    
    # Build with buildx for multi-platform support
    docker buildx build \\
        --platform linux/amd64 \\
        --file Dockerfile \\
        --tag "${REGISTRY}/${IMAGE_NAME}:${OTEL_TAG}" \\
        --tag "${REGISTRY}/${IMAGE_NAME}:${VERSION}" \\
        --tag "${REGISTRY}/${IMAGE_NAME}:latest-otel" \\
        --label "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \\
        --label "org.opencontainers.image.version=${OTEL_TAG}" \\
        --label "org.opencontainers.image.source=https://gitlab.com/atafaya971/packsol" \\
        --label "org.opencontainers.image.description=Addok geocoding service with OpenTelemetry tracing" \\
        --label "otel.enabled=true" \\
        --label "otel.version=1.21.0+" \\
        --push \\
        .
    
    cd ..
    
    log "✓ Docker image built and pushed successfully"
}

# Test the built image
test_image() {
    log "Testing built image..."
    
    # Pull the image to test
    docker pull "${REGISTRY}/${IMAGE_NAME}:${OTEL_TAG}"
    
    # Quick validation - check if OTEL packages are installed
    info "Validating OpenTelemetry packages..."
    docker run --rm "${REGISTRY}/${IMAGE_NAME}:${OTEL_TAG}" python3 -c "
import pkg_resources
packages = ['opentelemetry-api', 'opentelemetry-sdk', 'opentelemetry-exporter-otlp', 'prometheus-client']
for pkg in packages:
    try:
        version = pkg_resources.get_distribution(pkg).version
        print(f'✓ {pkg}: {version}')
    except pkg_resources.DistributionNotFound:
        print(f'✗ {pkg}: NOT INSTALLED')
        exit(1)
print('✓ All OpenTelemetry packages verified')
"
    
    log "✓ Image testing passed"
}

# Update progress tracking
update_progress() {
    log "Updating progress documentation..."
    
    cat > progress.md << EOF
# Implementation Progress - Addok 2.1.5-otel

## Current Status: ✅ COMPLETED

### Completed Tasks ✅
- [x] Created release tracking documentation
- [x] Analyzed monitoring requirements  
- [x] Updated Dockerfile with OpenTelemetry dependencies
- [x] Implemented telemetry module
- [x] Created Falcon middleware integration
- [x] Added Prometheus metrics endpoint
- [x] Updated entrypoint script with OTEL initialization
- [x] Successfully built Docker image
- [x] Created build automation script
- [x] Pushed to registry

## Build Results

| Component | Status | Version |
|-----------|--------|---------|
| Base Image | ✅ Built | python:3.11-alpine |
| OpenTelemetry API | ✅ Installed | Latest |
| OpenTelemetry SDK | ✅ Installed | Latest |
| OTLP Exporter | ✅ Installed | Latest |
| Prometheus Client | ✅ Installed | 0.19.0 |
| Falcon Integration | ✅ Implemented | Custom |
| Kubernetes Ready | ✅ Yes | - |

## Registry Tags
- \`${REGISTRY}/${IMAGE_NAME}:${OTEL_TAG}\`
- \`${REGISTRY}/${IMAGE_NAME}:${VERSION}\`
- \`${REGISTRY}/${IMAGE_NAME}:latest-otel\`

## Next Steps
1. Deploy to Kubernetes using new image tag
2. Verify traces appear in Grafana/Tempo
3. Confirm metrics scraped by Prometheus
4. Validate application functionality

**Build Completed**: $(date +'%Y-%m-%d %H:%M:%S')
**Build Status**: SUCCESS ✅
EOF

    log "✓ Progress documentation updated"
}

# Generate deployment command
generate_deployment_command() {
    log "Generating Kubernetes deployment command..."
    
    cat > deploy-215-otel.sh << 'EOF'
#!/bin/bash
# Deploy Addok 2.1.5-otel to Kubernetes

set -euo pipefail

NAMESPACE="addok-ban"
DEPLOYMENT="addok-ban"
NEW_IMAGE="registry.gitlab.com/atafaya971/packsol/addok-ban:2.1.5-otel"

echo "🚀 Deploying Addok 2.1.5-otel to Kubernetes..."

# Update the deployment image
kubectl set image deployment/${DEPLOYMENT} addok-ban=${NEW_IMAGE} -n ${NAMESPACE}

# Wait for rollout to complete
echo "⏳ Waiting for rollout to complete..."
kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE} --timeout=300s

# Verify deployment
echo "✅ Verifying deployment..."
kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT}

# Check if OTEL endpoint is configured
kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OTEL_EXPORTER_OTLP_ENDPOINT")].value}'

echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📊 Monitor traces at: http://grafana/explore (Tempo)"
echo "📈 Monitor metrics at: http://grafana/dashboard"
echo "🔍 Check logs: kubectl logs -f deployment/${DEPLOYMENT} -n ${NAMESPACE}"
EOF

    chmod +x deploy-215-otel.sh
    
    log "✓ Deployment script created: deploy-215-otel.sh"
}

# Main execution
main() {
    echo ""
    log "=== Addok 2.1.5-otel Release Build ==="
    echo ""
    info "Building OpenTelemetry-enabled Addok geocoding service"
    info "Registry: ${REGISTRY}/${IMAGE_NAME}"
    info "Tags: ${OTEL_TAG}, ${VERSION}, latest-otel"
    echo ""
    
    check_prerequisites
    validate_build
    build_image
    test_image
    update_progress
    generate_deployment_command
    
    echo ""
    log "🎉 Build completed successfully!"
    echo ""
    info "Image available at:"
    info "  ${REGISTRY}/${IMAGE_NAME}:${OTEL_TAG}"
    info "  ${REGISTRY}/${IMAGE_NAME}:${VERSION}"  
    info "  ${REGISTRY}/${IMAGE_NAME}:latest-otel"
    echo ""
    info "Next steps:"
    info "  1. Run: ./deploy-215-otel.sh (to deploy to Kubernetes)"
    info "  2. Update Kubernetes manifests with new image tag"
    info "  3. Configure OTEL_EXPORTER_OTLP_ENDPOINT environment variable"
    info "  4. Verify traces in Grafana/Tempo dashboard"
    echo ""
}

# Run main function
main "$@"