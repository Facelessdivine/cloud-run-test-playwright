FROM mcr.microsoft.com/playwright:v1.56.1-jammy

# Install gcloud CLI (for uploading reports)
RUN apt-get update && apt-get install -y curl gnupg \
 && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list \
 && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
 && apt-get update && apt-get install -y google-cloud-cli \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Node deps
COPY package*.json ./
RUN npm ci

# Make sure browsers for 1.56.1 are installed
RUN npx playwright install --with-deps

# Copy your tests + config
COPY . .

RUN chmod +x run-tests.sh

ENTRYPOINT ["bash", "./run-tests.sh"]
