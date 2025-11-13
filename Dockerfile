FROM mcr.microsoft.com/playwright:v1.48.0-jammy

# Install gcloud CLI (for uploading reports)
RUN apt-get update && apt-get install -y curl gnupg \
 && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list \
 && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
 && apt-get update && apt-get install -y google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 1) Install deps (Node)
COPY package*.json ./
RUN npm ci

# 2) 🔴 INSTALL PLAYWRIGHT BROWSERS INSIDE THE IMAGE
RUN npx playwright install --with-deps

# 3) Copy your tests + config
COPY . .

# 4) Ensure runner script is executable
RUN chmod +x run-tests.sh

ENTRYPOINT ["bash", "./run-tests.sh"]
