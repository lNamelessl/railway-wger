# Deploy and Host wger Workout Manager

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/wger-workout-manager)

Self-hosted **wger** (2.8-dev, official `wger/server` image, digest-pinned) — the workout and
nutrition manager with an exercise database, routine planner, weight and nutrition tracking,
and a full REST API used by the official Flutter app.

One click provisions **four services**: the wger web container (Django + gunicorn + bundled
nginx for static and media files), a Celery worker with the beat scheduler combined, Railway
Postgres, and Railway Redis. First boot migrates the database, loads the bundled exercise
fixtures, generates a fresh JWT keypair, and **replaces the shipped `admin/adminadmin`
account password with a per-deployment generated secret** (`WGER_ADMIN_PASSWORD`, visible in
the Variables tab) before the server accepts its first request.

## About Hosting

The web container runs the stock Django stack on gunicorn (port 8000, internal) behind a
bundled nginx listening on the Railway-injected port (domain targetPort 8080). nginx serves
`/static/` and `/media/` directly from disk — wger does not serve static files in production
on its own, which is why this template keeps the upstream nginx architecture inside the same
container instead of a separate sidecar (Railway volumes cannot be shared across services).

- **web** — wrapper image built from the pinned `wger/server` digest; volume at `/home/wger/media`
  (user uploads, downloaded exercise images, JWT keypair); healthcheck at `/api/v2/version`.
- **celery** — the same digest-pinned image with a start command running a combined Celery
  worker and beat scheduler (`celery worker -B`, volume at `/home/wger/beat`); handles the
  weekly exercise and ingredient sync and the API cache warming.
- **Postgres** — Railway's Postgres plugin; wired via `${{Postgres.*}}` references.
- **Redis** — Railway's Redis plugin; Django cache (db 1), Celery broker and backend (db 2).

Exercise data: bundled fixtures give you a working exercise database immediately on first
boot (offline, no network needed). The Celery weekly job keeps exercise and ingredient data in
sync with wger.de. Exercise images and videos are NOT downloaded by the Celery job — Railway
volumes are per-service, so media downloaded by the worker would never reach the web
container. Set `DOWNLOAD_EXERCISE_IMAGES_ON_STARTUP=True` on web to fetch images during first
boot, or run `python3 manage.py download-exercise-images` once from the web service shell.

## Why Deploy

Deploying wger manually means assembling seven upstream compose services (web, nginx sidecar,
PowerSync, Postgres, Redis, Celery worker, Celery beat) and editing env files by hand. This
template does the Railway-specific glue for you:

- The shipped `admin/adminadmin` fixture account is password-seeded on first boot, before
  gunicorn accepts traffic — no window where a public URL exposes the default credentials.
- A fresh RS256 JWT keypair is generated per deployment (the upstream default keys are public
  knowledge). Required for the REST API and the official mobile app.
- Sessions survive restarts: `SECRET_KEY` is a per-deployment generated secret, not the
  upstream default (which regenerates every boot and invalidates all sessions).
- PowerSync (mobile offline-sync) and the nginx sidecar are omitted on purpose; everything
  else matches upstream behavior, and the tradeoffs are documented above.

## Common Use Cases

- Personal workout and body-weight tracking with routine planning and progress charts.
- Nutrition diary with a large ingredient database and barcode-friendly lookups.
- A private API backend for the official wger Flutter app (JWT keypair is provisioned).
- Family or small-group instances — registration can stay open, guest accounts stay off.

## Dependencies for

Postgres and Redis are provisioned automatically by the template. All required environment
variables carry per-deployment generated defaults — the deploy form prompts for nothing.

### Deployment Dependencies

- Railway Postgres (`${{Postgres.PGDATABASE}}`, `${{Postgres.PGUSER}}`, `${{Postgres.PGPASSWORD}}`,
  `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}` feed `DJANGO_DB_*` on web and celery).
- Railway Redis (`${{Redis.REDIS_URL}}` feeds the Django cache and Celery broker/backend).
- Outbound HTTPS to `wger.de` for the weekly data sync jobs.
- `SECRET_KEY` and `WGER_ADMIN_PASSWORD` use per-deployment generated secrets; change the
  admin password in the UI after first login (the variable seed only replaces the shipped
  default once).

## Post-deploy steps

1. Open the Variables tab and reveal `WGER_ADMIN_PASSWORD`.
2. Log in at the generated domain as `admin` with that password and change it under your
   account settings.
3. Optional: enable exercise images (`DOWNLOAD_EXERCISE_IMAGES_ON_STARTUP=True` on web, then
   redeploy) or fetch them once from the web service shell.

## License and credits

wger is AGPL-3.0-or-later, upstream at https://github.com/wger-project/wger (docker stack:
https://github.com/wger-project/docker). This repository only packages the deployment for
Railway.
