# Builder stage
FROM node:22 AS installer
WORKDIR /juice-shop

# Copy manifests first for better caching
COPY package.json package-lock.json ./

# Install dependencies securely
RUN npm ci --omit=dev && \
    npm dedupe --omit=dev && \
    npm cache clean --force

# Copy source code
COPY . .

# Pin global tools to known versions
RUN npm install -g typescript@5.6.3 ts-node@10.9.2

# Clean up unnecessary frontend artifacts in one layer
RUN rm -rf frontend/node_modules frontend/.angular frontend/src/assets && \
    mkdir -p logs && \
    chown -R 65532 logs && \
    chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/ || true && \
    chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/ || true && \
    rm -f data/chatbot/botDefaultTrainingData.json \
          ftp/legal.md \
          i18n/*.json

# SBOM generation (merged into one RUN)
ARG CYCLONEDX_NPM_VERSION="0.5.2"
RUN npm install -g "@cyclonedx/cyclonedx-npm@${CYCLONEDX_NPM_VERSION}" && \
    npm run sbom

# Runtime stage
FROM gcr.io/distroless/nodejs22-debian12
ARG BUILD_DATE
ARG VCS_REF
LABEL maintainer="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
    org.opencontainers.image.title="OWASP Juice Shop" \
    org.opencontainers.image.description="Probably the most modern and sophisticated insecure web application" \
    org.opencontainers.image.authors="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
    org.opencontainers.image.vendor="Open Worldwide Application Security Project" \
    org.opencontainers.image.documentation="https://help.owasp-juice.shop" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.version="19.1.1" \
    org.opencontainers.image.url="https://owasp-juice.shop" \
    org.opencontainers.image.source="https://github.com/juice-shop/juice-shop" \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.created=$BUILD_DATE

WORKDIR /juice-shop
COPY --from=installer --chown=65532:0 /juice-shop .

USER 65532
EXPOSE 3000
CMD ["/juice-shop/build/app.js"]
