cat > Dockerfile << 'EOF'
FROM mcr.microsoft.com/playwright:v1.48.0-jammy

# Install gcloud CLI (to upload reports to GCS if BUCKET is set)
RUN apt-get update && apt-get install -y curl gnupg \
 && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list \
 && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
 && apt-get update && apt-get install -y google-cloud-cli \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install deps first (better caching)
COPY package*.json ./
RUN npm ci

# Copy the rest of your tests + config
COPY . .

# Ensure runner script is executable
RUN chmod +x run-tests.sh

# Default entrypoint: run one shard
ENTRYPOINT ["bash", "./run-tests.sh"]
EOF
