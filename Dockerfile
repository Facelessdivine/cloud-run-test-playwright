FROM mcr.microsoft.com/playwright:v1.56.1-jammy

WORKDIR /app

COPY package*.json ./
RUN npm ci

RUN npx playwright install --with-deps

COPY . .

RUN chmod +x run-tests.sh

ENTRYPOINT ["bash", "./run-tests.sh"]