#!/usr/bin/env bash
set -euo pipefail

# Verify required environment variables are set
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID not set}"
: "${MCP_OIDC_CLIENT_ID:?MCP_OIDC_CLIENT_ID not set}"
: "${MCP_OIDC_CLIENT_SECRET:?MCP_OIDC_CLIENT_SECRET not set}"
: "${CONTEXT7_API_KEY:?CONTEXT7_API_KEY not set}"
: "${FIRECRAWL_API_KEY:?FIRECRAWL_API_KEY not set}"
: "${LINKUP_API_KEY:?LINKUP_API_KEY not set}"
: "${OPENMEMORY_API_KEY:?OPENMEMORY_API_KEY not set}"
: "${PERPLEXITY_API_KEY:?PERPLEXITY_API_KEY not set}"

# Configuration
REGION="${GCP_REGION:-us-central1}"
ZONE="${REGION}-a"
MACHINE_TYPE="e2-small"
IMAGE_NAME="mcp-gateway"
FULL_IMAGE_NAME="${REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/mcp-gateway/${IMAGE_NAME}:latest"
MCP_DOMAIN="${MCP_DOMAIN:-mcp.example.com}"

echo "==> Creating Artifact Registry repository if needed..."
if ! gcloud artifacts repositories describe mcp-gateway \
    --project="${GCP_PROJECT_ID}" \
    --location="${REGION}" &>/dev/null; then
    echo "==> Repository doesn't exist, creating..."
    gcloud artifacts repositories create mcp-gateway \
        --project="${GCP_PROJECT_ID}" \
        --repository-format=docker \
        --location="${REGION}" \
        --description="MCP Gateway container images"
else
    echo "==> Artifact Registry repository already exists"
fi

echo ""
echo "==> Building and pushing Docker image..."
docker build -t "${IMAGE_NAME}" .
docker tag "${IMAGE_NAME}" "${FULL_IMAGE_NAME}"

echo "==> Configuring Docker for Artifact Registry..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

docker push "${FULL_IMAGE_NAME}"

echo ""
echo "==> Reserving static IP if needed..."
if ! gcloud compute addresses describe mcp-gateway-ip \
    --project="${GCP_PROJECT_ID}" \
    --region="${REGION}" &>/dev/null; then
    echo "==> Static IP doesn't exist, creating..."
    gcloud compute addresses create mcp-gateway-ip \
        --project="${GCP_PROJECT_ID}" \
        --region="${REGION}"
else
    echo "==> Static IP already exists, reusing..."
fi

# Get the static IP address
MCP_GATEWAY_IP=$(gcloud compute addresses describe mcp-gateway-ip \
    --project="${GCP_PROJECT_ID}" \
    --region="${REGION}" \
    --format='get(address)')
echo "==> Static IP: ${MCP_GATEWAY_IP}"

echo ""
echo "==> Creating firewall rules if needed..."
if ! gcloud compute firewall-rules describe allow-mcp-https \
    --project="${GCP_PROJECT_ID}" &>/dev/null; then
    echo "==> Creating HTTPS firewall rule..."
    gcloud compute firewall-rules create allow-mcp-https \
        --project="${GCP_PROJECT_ID}" \
        --allow=tcp:443,tcp:80 \
        --target-tags=https-server \
        --description="Allow HTTPS traffic for mcp-gateway"
else
    echo "==> Firewall rules already exist"
fi

echo ""
echo "==> Checking if VM exists..."
if gcloud compute instances describe mcp-gateway \
    --project="${GCP_PROJECT_ID}" \
    --zone="${ZONE}" &>/dev/null; then
    echo "==> VM exists, deleting and recreating..."
    
    gcloud compute instances delete mcp-gateway \
        --project="${GCP_PROJECT_ID}" \
        --zone="${ZONE}" \
        --quiet
    
    echo "==> VM deleted, proceeding with new deployment..."
fi

echo ""
echo "==> Granting Artifact Registry access to compute service account..."
PROJECT_NUMBER=$(gcloud projects describe "${GCP_PROJECT_ID}" --format='value(projectNumber)')
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "==> Using service account: ${COMPUTE_SA}"
gcloud artifacts repositories add-iam-policy-binding mcp-gateway \
    --project="${GCP_PROJECT_ID}" \
    --location="${REGION}" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/artifactregistry.reader" \
    --quiet || echo "Warning: Failed to grant IAM permissions (may already exist)"

echo ""
echo "==> Creating startup script..."
cat > /tmp/mcp-gateway-startup.sh <<'EOF'
#!/bin/bash
set -e

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Configure Docker for Artifact Registry
gcloud auth configure-docker ${GCP_REGION}-docker.pkg.dev --quiet

# Pull and run the gateway container
docker pull ${FULL_IMAGE_NAME}

docker run -d \
  --name mcp-gateway \
  --restart unless-stopped \
  -p 443:443 \
  -p 80:80 \
  -e MCP_OIDC_CLIENT_ID="${MCP_OIDC_CLIENT_ID}" \
  -e MCP_OIDC_CLIENT_SECRET="${MCP_OIDC_CLIENT_SECRET}" \
  -e MCP_DOMAIN="${MCP_DOMAIN}" \
  -e MCP_ALLOWED_USERS="${MCP_ALLOWED_USERS}" \
  -e CONTEXT7_API_KEY="${CONTEXT7_API_KEY}" \
  -e FIRECRAWL_API_KEY="${FIRECRAWL_API_KEY}" \
  -e LINKUP_API_KEY="${LINKUP_API_KEY}" \
  -e OPENMEMORY_API_KEY="${OPENMEMORY_API_KEY}" \
  -e PERPLEXITY_API_KEY="${PERPLEXITY_API_KEY}" \
  ${FULL_IMAGE_NAME}

echo "MCP Gateway started successfully"
EOF

# Substitute variables in startup script
export FULL_IMAGE_NAME
export GCP_REGION="${REGION}"
export MCP_OIDC_CLIENT_ID
export MCP_OIDC_CLIENT_SECRET
export MCP_DOMAIN
export MCP_ALLOWED_USERS
export CONTEXT7_API_KEY
export FIRECRAWL_API_KEY
export LINKUP_API_KEY
export OPENMEMORY_API_KEY
export PERPLEXITY_API_KEY

envsubst '$FULL_IMAGE_NAME $GCP_REGION $MCP_OIDC_CLIENT_ID $MCP_OIDC_CLIENT_SECRET $MCP_DOMAIN $MCP_ALLOWED_USERS $CONTEXT7_API_KEY $FIRECRAWL_API_KEY $LINKUP_API_KEY $OPENMEMORY_API_KEY $PERPLEXITY_API_KEY' < /tmp/mcp-gateway-startup.sh > /tmp/mcp-gateway-startup-final.sh

echo ""
echo "==> Creating new VM..."
gcloud compute instances create mcp-gateway \
    --project="${GCP_PROJECT_ID}" \
    --zone="${ZONE}" \
    --machine-type="${MACHINE_TYPE}" \
    --network-interface=address="${MCP_GATEWAY_IP}",network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced \
    --metadata-from-file=startup-script=/tmp/mcp-gateway-startup-final.sh \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --tags=https-server \
    --shielded-vtpm \
    --shielded-integrity-monitoring

echo ""
echo "==> Deployment complete!"
echo "==> VM IP (Static): ${MCP_GATEWAY_IP}"
echo "==> Domain: ${MCP_DOMAIN}"
echo ""
echo "Point ${MCP_DOMAIN} DNS A record to ${MCP_GATEWAY_IP}"
echo ""
echo "==> Waiting for Docker to be installed and container to start..."
echo "==> This may take 2-3 minutes (installing Docker, pulling image, starting container)"
echo ""

# Poll until docker is available and container is running
for i in {1..60}; do
    echo "==> Attempt $i/60: Checking if container is running..."
    if gcloud compute ssh mcp-gateway \
        --project="${GCP_PROJECT_ID}" \
        --zone="${ZONE}" \
        --command='docker ps --filter name=mcp-gateway --format "{{.Status}}"' 2>/dev/null | grep -q "Up"; then
        echo "==> Container is running!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "==> Timeout waiting for container. Check startup logs with:"
        echo "    gcloud compute ssh mcp-gateway --project=${GCP_PROJECT_ID} --zone=${ZONE} --command='sudo journalctl -u google-startup-scripts.service'"
        exit 1
    fi
    sleep 5
done

echo ""
echo "==> Tailing container logs (Ctrl+C to stop)..."
echo ""

gcloud compute ssh mcp-gateway \
    --project="${GCP_PROJECT_ID}" \
    --zone="${ZONE}" \
    --command='docker logs -f mcp-gateway'
