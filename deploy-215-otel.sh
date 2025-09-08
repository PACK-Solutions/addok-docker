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
