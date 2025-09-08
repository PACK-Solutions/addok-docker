# Grafana Dashboards for Addok OpenTelemetry

## Available Dashboards

### 1. `addok-overview.json` - Main Service Overview
**Purpose**: Monitor overall Addok service performance and health

**Panels**:
- Request rate (req/s) by endpoint and status
- P95 response time (ms)
- Error rate by error type and endpoint  
- Cache hit rate percentage
- Active concurrent requests
- Memory usage (bytes)
- CPU usage (%)

**Best for**: Real-time monitoring, SLA tracking, general health

### 2. `addok-csv.json` - CSV Processing Dashboard
**Purpose**: Monitor batch CSV geocoding operations

**Panels**:
- CSV upload rate by operation type
- Processing duration (P50/P95 percentiles)
- Rows processed per second
- Current processing status
- Success vs error rates by operation

**Best for**: Batch processing monitoring, CSV performance tuning

## Import Instructions

### Method 1: Grafana UI Import
1. Open Grafana → **Dashboards** → **Import**
2. Click **Upload JSON file**
3. Select the dashboard file (`.json`)
4. Configure datasource (select your Prometheus instance)
5. Click **Import**

### Method 2: Grafana API Import
```bash
# Import Overview Dashboard
curl -X POST http://grafana:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d @addok-overview.json

# Import CSV Dashboard  
curl -X POST http://grafana:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d @addok-csv.json
```

### Method 3: Kubernetes ConfigMap (GitOps)
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: addok-dashboards
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  addok-overview.json: |
    {{ .Files.Get "addok-overview.json" | nindent 4 }}
  addok-csv.json: |
    {{ .Files.Get "addok-csv.json" | nindent 4 }}
```

## Required Metrics

These dashboards expect the following Prometheus metrics to be available:

### OpenTelemetry Metrics (from app)
- `addok_geocoding_requests_total`
- `addok_geocoding_request_duration_seconds`
- `addok_csv_uploads_total`
- `addok_csv_rows_processed_total`
- `addok_csv_processing_duration_seconds`
- `addok_cache_hits_total` / `addok_cache_misses_total`
- `addok_errors_total`
- `addok_active_requests`

### Prometheus Metrics (from /metrics endpoint)
- `addok_memory_usage_bytes`
- `addok_cpu_usage_percent`
- `addok_csv_processing_total`
- `addok_csv_rows_processed_current`

## Customization

### Update Prometheus Job Name
If your Prometheus job name is different from `addok-ban`, update all queries:
```
{job="addok-ban"} → {job="your-job-name"}
```

### Add Instance Filtering
For multi-instance deployments, add instance selector:
```
{job="addok-ban",instance=~"$instance"}
```

Then add a template variable for `$instance`.

### Adjust Time Ranges
- **Overview Dashboard**: Default 1 hour (`now-1h` to `now`)
- **CSV Dashboard**: Default 6 hours (`now-6h` to `now`)

## Alerting Integration

The dashboards are designed to work with these alert rules:

```yaml
# Example alert rules
- alert: AddokHighErrorRate
  expr: rate(addok_errors_total[5m]) > 0.1
  
- alert: AddokHighResponseTime  
  expr: histogram_quantile(0.95, rate(addok_geocoding_request_duration_seconds_bucket[5m])) > 1
  
- alert: AddokLowCacheHitRate
  expr: rate(addok_cache_hits_total[10m]) / (rate(addok_cache_hits_total[10m]) + rate(addok_cache_misses_total[10m])) < 0.7
```

## Troubleshooting

### No Data Showing
1. **Check ServiceMonitor**: Ensure Prometheus is scraping `/metrics` endpoint
2. **Verify Job Name**: Confirm `job` label matches dashboard queries
3. **Check OTEL Export**: Verify traces/metrics reaching Alloy → Prometheus

### Missing Panels
1. **Metrics Missing**: Check if specific metrics are being exported
2. **Datasource Config**: Verify Prometheus datasource UID
3. **Query Syntax**: Check PromQL query syntax for your Prometheus version

## Dashboard UIDs
- `addok_overview` - Main overview dashboard
- `addok_csv` - CSV processing dashboard

These can be referenced in alerts, links, or other dashboards.