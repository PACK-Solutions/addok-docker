#!/bin/bash
# Deploy Addok 2.1.6-dual to Kubernetes

set -euo pipefail

NAMESPACE="addok-ban"
DEPLOYMENT="addok-ban"
NEW_IMAGE="registry.gitlab.com/atafaya971/packsol/addok-ban:2.1.6-dual"

echo "🚀 Deploying Addok 2.1.6-dual with dual observability to Kubernetes..."

# Update the deployment image
kubectl set image deployment/${DEPLOYMENT} addok-ban=${NEW_IMAGE} -n ${NAMESPACE}

# Wait for rollout to complete
echo "⏳ Waiting for rollout to complete..."
kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE} --timeout=300s

# Verify deployment
echo "✅ Verifying deployment..."
kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT}

# Check observability configuration
echo "🔍 Checking observability configuration..."
echo "OpenTelemetry endpoint:"
kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OTEL_EXPORTER_OTLP_ENDPOINT")].value}'
echo ""
echo "Datadog configuration:"
kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DD_AGENT_HOST")].value}'
echo ""

echo ""
echo "🎉 Dual observability deployment completed successfully!"
echo ""
echo "📊 Monitor OpenTelemetry traces at: http://grafana/explore (Tempo)"
echo "📈 Monitor OpenTelemetry metrics at: http://grafana/dashboard"
echo "🐶 Monitor Datadog traces at: https://app.datadoghq.com/apm/services"
echo "📋 Monitor Datadog metrics at: https://app.datadoghq.com/infrastructure"
echo "🔍 Check logs: kubectl logs -f deployment/${DEPLOYMENT} -n ${NAMESPACE}"
echo ""
echo "🔧 Validate dual stack:"
echo "  curl http://addok-ban/search?q=paris (should generate traces in both systems)"
echo "  curl http://addok-ban/metrics (should show Prometheus metrics)"
