# syntax=docker/dockerfile:1

# ---- Composer dependencies --------------------------------------------------
# --ignore-platform-reqs: the composer image lacks the extensions the app
# requires; the runtime image installs them. composer.lock pins the versions.
FROM composer:2 AS vendor

WORKDIR /app

ARG COMPOSER_AUTH
ENV COMPOSER_ALLOW_SUPERUSER=1

COPY composer.json composer.lock ./
RUN COMPOSER_AUTH="${COMPOSER_AUTH}" composer install \
        --no-dev \
        --prefer-dist \
        --no-interaction \
        --no-progress \
        --optimize-autoloader \
        --no-scripts \
        --ignore-platform-reqs


# ---- Portal assets (Vite) ---------------------------------------------------
# Node 22: a transitive dependency (pdfjs-dist via @docuninja/builder2.0)
# requires >= 22.13.
FROM node:22-bookworm-slim AS assets

WORKDIR /app

# resources/js/app.js imports Livewire from vendor/, so the Composer
# dependencies must be present before the Vite build runs.
COPY --from=vendor /app/vendor ./vendor

COPY package.json package-lock.json ./
# The committed lock file can drift from package.json, which makes npm ci fail;
# fall back to a normal install so the image build is not blocked by it.
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund

COPY vite.config.ts postcss.config.cjs tailwind.config.cjs ./
COPY resources ./resources
COPY public ./public

# Writes public/build. The React admin bundle lives in public/build-admin and is
# committed to the repository, so this build must not touch it.
RUN npm run build


# ---- Runtime (FrankenPHP) ---------------------------------------------------
FROM dunglas/frankenphp:1-php8.3

# Extensions required by composer.json and by the optional dependencies the app
# uses at runtime (intervention/image, nelexa/zip, queue workers, Redis).
RUN install-php-extensions \
    bcmath \
    exif \
    gd \
    intl \
    mbstring \
    opcache \
    pcntl \
    pdo_mysql \
    redis \
    zip

# Chromium backs the Snappdf PDF generator (PDF_GENERATOR=snappdf).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        chromium \
        fonts-liberation \
        curl \
        git \
        unzip \
    && rm -rf /var/lib/apt/lists/*

ENV SNAPPDF_CHROMIUM_PATH=/usr/bin/chromium
ENV COMPOSER_ALLOW_SUPERUSER=1

WORKDIR /app

COPY --from=vendor /app/vendor ./vendor
COPY . .
COPY --from=assets /app/public/build ./public/build

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN mkdir -p \
        bootstrap/cache \
        storage/app/public \
        storage/framework/cache \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R ug+rwX storage bootstrap/cache

COPY Caddyfile /etc/frankenphp/Caddyfile
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV SERVER_NAME=:8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]
