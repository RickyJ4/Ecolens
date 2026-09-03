# ═══════════════════════════════════════════════════════════════════════
# EcoLens Cartographic Intelligence Engine — QGIS Container
#
# Deploys to Google Cloud Run with full PyQGIS rendering capabilities.
# Based on official QGIS Docker image with Python dependencies added.
#
# Build:
#   docker build -t ecolens-cartographic -f cartographic/Dockerfile .
#
# Run locally:
#   docker run -p 8080:8080 -e PORT=8080 ecolens-cartographic
#
# Test QGIS availability:
#   docker run --rm ecolens-cartographic python3 -c "from qgis.core import *; print('QGIS OK')"
#
# Deploy to Cloud Run:
#   gcloud builds submit --tag gcr.io/PROJECT_ID/ecolens-cartographic
#   gcloud run deploy ecolens-cartographic \
#     --image gcr.io/PROJECT_ID/ecolens-cartographic \
#     --memory 2Gi --timeout 540 --concurrency 4
# ═══════════════════════════════════════════════════════════════════════

FROM qgis/qgis:release-3_34

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV QT_QPA_PLATFORM=offscreen
ENV QGIS_PREFIX_PATH=/usr
ENV PYTHONDONTWRITEBYTECODE=1

# Install system dependencies for cartographic rendering
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-dev \
    fonts-noto \
    fonts-noto-cjk \
    fonts-liberation \
    fonts-dejavu \
    libgdal-dev \
    && rm -rf /var/lib/apt/lists/*

# Working directory
WORKDIR /app

# Copy requirements and install Python deps
COPY ecolens/functions/requirements.txt /app/requirements.txt
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt
RUN pip3 install --no-cache-dir --break-system-packages \
    gunicorn \
    flask \
    functions-framework

# Copy application code
COPY ecolens/functions/ /app/

# Copy the cartographic engine (source of truth)
COPY cartographic/ /app/cartographic/

# Verify QGIS works
RUN python3 -c "from qgis.core import QgsApplication; print('PyQGIS import OK')"

# Cloud Run expects PORT environment variable
ENV PORT=8080

# Entry point: serve Cloud Functions via functions-framework
# This serves the same endpoints as Firebase Cloud Functions
CMD exec gunicorn \
    --bind :$PORT \
    --workers 2 \
    --threads 4 \
    --timeout 540 \
    --worker-class gthread \
    main:app 2>/dev/null || \
    functions-framework \
    --target=generate_cartographic_map \
    --port=$PORT \
    --debug
