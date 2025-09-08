# Report: Enabling Large CSV File Uploads (15MB - 100MB)

## Current Situation
- ✅ **Works**: `search_1.csv` (99 rows, ~15KB)
- ❌ **Fails**: `search_100k.csv` (100,000 rows, ~15MB) 
- ❌ **Will Fail**: `search_400k.csv` (400,000 rows, ~62MB)

**Error**: `"body part is too large"` from Falcon's multipart parser

## Root Cause Analysis

### 1. **Primary Bottleneck: Falcon Multipart Parser**
- **Default limit**: 1MB per body part (`max_body_part_buffer_size`)
- **Your file**: 15MB (15x over limit)
- **Location**: Falcon framework's multipart form handler
- **Error message**: Exactly matches your "body part is too large"

### 2. **Secondary Limits to Consider**
- **Nginx** (if present): Often defaults to 1-5MB (`client_max_body_size`)
- **Gunicorn timeout**: 30 seconds may be insufficient for processing large files
- **Memory usage**: 100k-400k rows will require significant RAM for processing

## Required Changes

### **File 1: `/addok/wsgi_otel.py`** (Primary Fix)
```python
# Add after line 56 (after strip_url_path_trailing_slash = True)
from falcon.media import MultipartParseOptions

multipart_options = MultipartParseOptions(
    max_body_part_buffer_size=100 * 1024 * 1024,  # 100MB (was 1MB)
    max_body_part_count=64,  # Allow multiple parts  
    max_body_part_headers_size=8192  # Header size limit
)

app.req_options.media_handlers[falcon.MEDIA_MULTIPART] = falcon.media.MultipartFormHandler(
    parse_options=multipart_options
)
```

### **File 2: `/addok/gunicorn.conf.py`** (Processing Timeout)
```python
# Increase timeout for large file processing
timeout = 120  # Increase from 30 seconds to 2 minutes
```

### **File 3: Check for nginx configuration** (If using reverse proxy)
```nginx
# In nginx.conf or site config
client_max_body_size 100M;  # Increase from default 1M-5M
```

### **File 4: Environment Variables** (Optional safety limits)
```bash
# In Dockerfile or deployment
ENV MAX_CSV_FILE_SIZE=104857600  # 100MB in bytes
ENV CSV_PROCESSING_TIMEOUT=120   # 2 minutes
```

## Impact Assessment

### **Memory Usage**
- **100k rows**: ~40-50MB RAM during processing
- **400k rows**: ~150-200MB RAM during processing
- **Workers**: 4 gunicorn workers could handle multiple simultaneous uploads

### **Processing Time**
- **Estimate**: 1-3 seconds per 100k rows for geocoding
- **Network**: Upload time depends on connection (15MB = ~1-10 seconds)
- **Total**: 30-60 seconds for 400k rows end-to-end

### **Storage**
- **Temporary**: Files stored in memory during processing
- **Results**: JSON response size will be large (similar to input size)

## Recommended Implementation Order

1. **Critical**: Update Falcon multipart limits in `wsgi_otel.py`
2. **Important**: Increase Gunicorn timeout in `gunicorn.conf.py` 
3. **Check**: Verify no nginx limits in deployment
4. **Test**: Deploy and test with 100k file
5. **Scale**: Test with 400k file if 100k succeeds

## Risk Mitigation

### **Memory Management**
- Monitor worker memory usage with large files
- Consider streaming processing for 400k+ rows
- Set reasonable upper limits (100MB max)

### **DoS Protection**
- Rate limiting on CSV endpoint
- File size validation before processing
- Timeout handling for stuck uploads

## Files That Need Changes

1. ✏️ `/addok/wsgi_otel.py` - **REQUIRED** (Falcon multipart limits)
2. ✏️ `/addok/gunicorn.conf.py` - **RECOMMENDED** (timeout)  
3. 🔍 Check nginx config - **IF PRESENT** (body size)
4. 🐳 Update Dockerfile - **OPTIONAL** (environment vars)

The **primary fix** is the Falcon multipart configuration. Without this, 15MB+ files will always fail with "body part is too large".