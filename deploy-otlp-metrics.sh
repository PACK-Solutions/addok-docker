#!/bin/bash
# Deploy OTLP Metrics Pipeline - Complete Implementation
# This script implements the unified OTLP pipeline (traces + metrics) through Alloy

set -euo pipefail

# Configuration
ADDOK_NAMESPACE="addok-ban"
MONITORING_NAMESPACE="monitoring"
ALLOY_RELEASE="alloy"
NEW_IMAGE="registry.gitlab.com/atafaya971/packsol/addok-ban:2.1.5-otel"

echo "🚀 Deploying OTLP Metrics Pipeline Implementation..."
echo ""
echo "📋 Implementation Overview:"
echo "  ✓ Unified OTLP pipeline: Addok → Alloy → (Tempo + Prometheus)"
echo "  ✓ Traces: OTLP → Alloy → Tempo → Grafana"
echo "  ✓ Metrics: OTLP → Alloy → Prometheus → Grafana"
echo "  ✓ Dual metrics collection: Direct scraping + OTLP forwarding"
echo ""

# Step 1: Update Alloy configuration with OTLP metrics support
echo "🔧 Step 1: Updating Alloy configuration..."
if helm upgrade ${ALLOY_RELEASE} grafana/alloy \
    --version 1.0.3 \
    --values /Users/npasquin/gitRepo/talos-homelab/components/monitoring/alloy-values.yaml \
    -n ${MONITORING_NAMESPACE} \
    --wait; then
    echo "✅ Alloy configuration updated successfully"
else
    echo "❌ Failed to update Alloy configuration"
    exit 1
fi

# Step 2: Wait for Alloy rollout
echo "⏳ Waiting for Alloy rollout to complete..."
kubectl rollout status deployment/alloy -n ${MONITORING_NAMESPACE} --timeout=300s

# Step 3: Verify Alloy metrics port is exposed
echo "🔍 Verifying Alloy service configuration..."
kubectl get svc alloy -n ${MONITORING_NAMESPACE} -o jsonpath='{.spec.ports[*].name}' || {
    echo "⚠️ Alloy service ports: $(kubectl get svc alloy -n ${MONITORING_NAMESPACE} -o yaml | grep -A10 ports:)"
}

# Step 4: Deploy updated Addok with OTLP metrics
echo "🚀 Step 4: Deploying Addok 2.1.5-otel with OTLP metrics..."
kubectl set image deployment/addok-ban addok-ban=${NEW_IMAGE} -n ${ADDOK_NAMESPACE}

# Step 5: Update environment variables for OTLP metrics
echo "🔧 Step 5: Configuring OTLP metrics environment..."
kubectl set env deployment/addok-ban \
    OTEL_EXPORTER_OTLP_ENDPOINT="http://alloy.monitoring:4317" \
    OTEL_METRICS_CONSOLE_DEBUG="true" \
    -n ${ADDOK_NAMESPACE}

# Step 6: Wait for Addok rollout
echo "⏳ Waiting for Addok rollout to complete..."
kubectl rollout status deployment/addok-ban -n ${ADDOK_NAMESPACE} --timeout=300s

# Step 7: Apply updated monitoring configuration
echo "📊 Step 7: Applying updated monitoring observability..."
kubectl apply -f /Users/npasquin/gitRepo/talos-homelab/applications/addok-ban-app/base/70-monitoring-observability.yaml

# Step 8: Verification checks
echo ""
echo "🔍 Verification Phase..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Alloy logs for OTLP metrics
echo "📝 Checking Alloy OTLP configuration..."
kubectl logs -l app.kubernetes.io/name=alloy -n ${MONITORING_NAMESPACE} --tail=50 | grep -i "otlp\|metrics\|prometheus" || true

# Check Addok telemetry initialization
echo "📝 Checking Addok OTLP metrics initialization..."
kubectl logs -l app=addok-ban -n ${ADDOK_NAMESPACE} --tail=20 | grep -i "✓ OTLP metrics initialized\|metrics" || true

# Verify ServiceMonitors
echo "📈 Verifying ServiceMonitors..."
echo "Direct metrics: $(kubectl get servicemonitor addok-ban-metrics -n ${ADDOK_NAMESPACE} -o jsonpath='{.metadata.name}' 2>/dev/null || echo 'Not found')"
echo "Alloy OTLP metrics: $(kubectl get servicemonitor alloy-otlp-metrics -n ${MONITORING_NAMESPACE} -o jsonpath='{.metadata.name}' 2>/dev/null || echo 'Not found')"

# Test endpoints
echo ""
echo "🌐 Testing Endpoints..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Port-forward and test Alloy metrics endpoint
echo "Testing Alloy Prometheus metrics endpoint..."
kubectl port-forward -n ${MONITORING_NAMESPACE} svc/alloy 8889:8889 &
PF_PID=$!
sleep 5

if curl -s http://localhost:8889/metrics | grep -q "addok_"; then
    echo "✅ Alloy OTLP metrics endpoint working"
else
    echo "⚠️ Alloy OTLP metrics endpoint may not be ready yet"
fi

kill $PF_PID 2>/dev/null || true

# Test a few requests to generate metrics
echo "🔄 Generating test traffic..."
kubectl port-forward -n ${ADDOK_NAMESPACE} svc/addok-ban 8080:80 &
PF_PID2=$!
sleep 3

for i in {1..5}; do
    curl -s "http://localhost:8080/search?q=paris" > /dev/null || true
    sleep 1
done

kill $PF_PID2 2>/dev/null || true

echo ""
echo "🎉 OTLP Metrics Pipeline Deployment Complete!"
echo ""
echo "📊 Monitoring Stack Architecture:"
echo "  ┌─────────────┐    OTLP     ┌───────────┐    Traces     ┌───────────┐"
echo "  │   Addok     │ ──────────► │   Alloy   │ ─────────────► │   Tempo   │"
echo "  │   2.1.5     │             │           │                │           │"
echo "  │             │             │           │    Prometheus  │           │"
echo "  │             │ ─ ─ ─ ─ ─ ─ ► │           │ ─────────────► │Prometheus │"
echo "  └─────────────┘   Direct    └───────────┘                │           │"
echo "                   Scraping        │                       └───────────┘"
echo "                                   │ Metrics                     │"
echo "                                   ▼                             │"
echo "                            ┌─────────────┐ ◄──────────────────────┘"
echo "                            │   Grafana   │         Queries"
echo "                            └─────────────┘"
echo ""
echo "🔗 Access Points:"
echo "  📈 Grafana: http://grafana/dashboard"
echo "  🔍 Tempo: http://grafana/explore (Tempo datasource)"
echo "  📊 Prometheus: http://prometheus/targets (check scraping status)"
echo ""
echo "📝 Next Steps:"
echo "  1. Check Prometheus targets: kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring"
echo "  2. Verify metrics in Grafana: Look for 'addok_*' metrics from both direct and OTLP sources"
echo "  3. Test distributed tracing: Make requests and check traces in Tempo"
echo "  4. Monitor both metric pipelines: Direct scraping + OTLP forwarding"
echo ""
echo "🐛 Troubleshooting:"
echo "  • Alloy logs: kubectl logs -l app.kubernetes.io/name=alloy -n monitoring -f"
echo "  • Addok logs: kubectl logs -l app=addok-ban -n addok-ban -f"
echo "  • ServiceMonitors: kubectl get servicemonitor -A"
echo "  • Prometheus config: kubectl get prometheus -o yaml -n monitoring"