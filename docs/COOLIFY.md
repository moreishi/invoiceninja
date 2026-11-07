# Deploying on Coolify

This branch ships a `Dockerfile` (FrankenPHP + PHP 8.3), a reference
`docker-compose.yml`, and this guide. The image serves HTTP on port **8080** and
exposes a health endpoint at **`/health`**.

## 1. Create the resource

1. In Coolify: **+ New → Application → Dockerfile**.
2. Repository/branch: this repo, branch `feature/premium-business-rebrand`.
3. Base directory: `/`.
4. Dockerfile location: `Dockerfile`.
5. **Port:** `8080`.
6. **Health check path:** `/health` (public route; no auth required).

### Build argument

The composer dependencies include two GitHub VCS packages (`invoiceninja/einvoice`,
`turbo124/snappdf`). Without a token the build can hit GitHub's anonymous rate
limit. Add a build-time variable:

```
COMPOSER_AUTH={"github-oauth":{"github.com":"ghp_xxxxxxxx"}
```

The value in `.env.example` (`${{ secrets.GITHUB_TOKEN }}`) is GitHub Actions
syntax and **will not** be expanded by Coolify.

## 2. Environment

Generate a fresh `APP_KEY` (the one in `.env.example` is public):

```sh
php -r "echo 'base64:'.base64_encode(random_bytes(32)).PHP_EOL;"
```

Minimum set:

| Variable | Value |
|---|---|
| `APP_NAME` | Your product name |
| `APP_ENV` | `production` |
| `APP_KEY` | generated above |
| `APP_URL` | `https://your-domain` |
| `APP_DEBUG` | `false` |
| `NINJA_ENVIRONMENT` | `selfhost` |
| `NINJA_PROD` | `false` |
| `DB_CONNECTION` | `mysql` (MariaDB works) |
| `DB_HOST` / `DB_DATABASE` / `DB_USERNAME` / `DB_PASSWORD` | your database |
| `REDIS_HOST` / `REDIS_PORT` / `REDIS_PASSWORD` | your Redis |
| `CACHE_DRIVER` | `redis` |
| `QUEUE_CONNECTION` | `redis` |
| `SESSION_DRIVER` | `redis` |
| `PDF_GENERATOR` | `snappdf` |
| `LICENSE_URL` | leave **empty** to stop the signup registration call |
| `VERSION_URL` | leave **empty** to stop the daily version ping |

`REDIS_CLIENT=predis` works without the `redis` PHP extension; the image ships
it either way.

## 3. Services (three, one image)

Coolify can run several services from the same image. Create the app once, then
duplicate it twice with a different start command:

| Service | Start command |
|---|---|
| web | `frankenphp run --config /etc/frankenphp/Caddyfile` (image default) |
| worker | `php artisan queue:work --tries=3 --timeout=120 --max-time=3600` |
| scheduler | `php artisan schedule:work` |

The **scheduler is not optional**: reminders, recurring invoices and the daily
`VersionCheck` (which enforces license expiry) only run there.

All three must share the same `storage/` volume.

## 4. First deploy

The entrypoint creates the storage skeleton and symlink. Set
`RUN_MIGRATIONS=true` on the web service for the first deploy (or run it
manually), then:

```sh
php artisan migrate --force
php artisan storage:link
```

Open `https://your-domain/setup` to run the setup wizard.

## 5. Verifying a deploy

```sh
php artisan about                # env, cache, drivers
php artisan migrate:status       # all migrations ran
curl -fsS https://your-domain/health
```

Then generate one invoice PDF (proves Chromium/Snappdf), send one queued email
(proves the worker) and confirm `schedule:work` logs a run.

## Known caveats

- **Schema dump excluded.** The image omits `database/schema/*.sql`, so `migrate`
  imports the individual migrations over PDO (~15s on a fresh database). The
  squashed schema is loaded by Laravel through the `mysql` CLI, and recent
  Debian MariaDB clients force TLS, which fails against servers without SSL.
  If you re-enable the dump, install `mariadb-client` and make your database
  accept TLS (or add `ssl=0` to the client config).
- **Flutter clients** in `public/` are prebuilt upstream artifacts and still call
  the removed `POST /api/v1/claim_license`. That action now returns 404.
- **React admin bundle** lives in `public/build-admin` and is committed; the Vite
  build in the image only rewrites `public/build`.
- The `composer.json` `path` repository `../admin-api` does not exist here;
  Composer logs a warning and skips it. Remove that entry if your pipeline treats
  Composer warnings as errors.
- Composer VCS dependencies require network access during the image build.
- The assets stage uses **Node 22**: `pdfjs-dist` (pulled in by
  `@docuninja/builder2.0`) requires >= 22.13, and the committed
  `package-lock.json` can drift from `package.json`, so the build falls back to
  `npm install` when `npm ci` rejects the lock.
