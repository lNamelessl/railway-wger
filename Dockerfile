# Railway template wrapper for the official wger server image.
#
# The stock image (USER wger, uid 1000) cannot serve /static/ and /media/ in
# production (upstream ships a separate nginx sidecar for that), and Railway
# volumes cannot be shared between services. This wrapper therefore folds
# nginx into the web container, seeded by the upstream nginx.conf, and adds:
#   - root-stage chown of Railway's root-owned volume mounts
#   - first-boot JWT keypair generation (persisted on the media volume)
#   - first-boot seeding of the admin password from WGER_ADMIN_PASSWORD
#     (the upstream image ships admin/adminadmin via a fixture)
#
# Base image digest pinned (wger/server:latest, manifest list, amd64+arm64).
FROM docker.io/wger/server@sha256:f256c13b356b295fa58cfc9d9ba7b691bc9615a05ec2bb58262ee83864b493d0

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx gosu \
    && rm -rf /var/lib/apt/lists/*

COPY docker/railway-entrypoint.sh /railway-entrypoint.sh
COPY docker/railway-entry-user.sh /home/wger/railway-entry-user.sh
COPY docker/nginx-railway.conf /etc/nginx/railway.conf

RUN chmod +x /railway-entrypoint.sh /home/wger/railway-entry-user.sh \
    && mkdir -p /home/wger/nginx-temp \
    && chown wger:wger /home/wger/railway-entry-user.sh /home/wger/nginx-temp

# ---- Static configuration (literals; kept out of the variable surface so
# ---- template deploys stay zero-prompt). Expressions like ${{secret(...)}} /
# ---- ${{Postgres.PGDATABASE}} are set as service variables instead.
ENV WGER_PORT=8000 \
    WGER_USE_GUNICORN=True \
    DJANGO_DEBUG=False \
    DJANGO_DB_ENGINE=django.db.backends.postgresql \
    DJANGO_DB_PORT=5432 \
    DJANGO_DB_USER=postgres \
    DJANGO_DB_DATABASE=postgres \
    DJANGO_PERFORM_MIGRATIONS=True \
    DJANGO_COLLECTSTATIC_ON_STARTUP=True \
    DJANGO_CLEAR_STATIC_FIRST=False \
    USE_CELERY=True \
    SYNC_EXERCISES_CELERY=True \
    SYNC_EXERCISE_IMAGES_CELERY=False \
    SYNC_EXERCISE_VIDEOS_CELERY=False \
    SYNC_INGREDIENTS_CELERY=True \
    CACHE_API_EXERCISES_CELERY=True \
    DOWNLOAD_INGREDIENTS_FROM=None \
    WGER_INSTANCE=https://wger.de \
    TIME_ZONE=UTC \
    TZ=UTC \
    ALLOW_REGISTRATION=True \
    ALLOW_GUEST_USERS=False \
    DJANGO_CACHE_BACKEND=django_redis.cache.RedisCache \
    DJANGO_CACHE_CLIENT_CLASS=django_redis.client.DefaultClient \
    DJANGO_CACHE_TIMEOUT=1296000 \
    X_FORWARDED_PROTO_HEADER_SET=True \
    NUMBER_OF_PROXIES=1 \
    AXES_ENABLED=True \
    AXES_FAILURE_LIMIT=10 \
    AXES_COOLOFF_TIME=30 \
    AXES_HANDLER=axes.handlers.cache.AxesCacheHandler \
    AXES_LOCKOUT_PARAMETERS=ip_address \
    AXES_IPWARE_PROXY_COUNT=0 \
    AXES_IPWARE_META_PRECEDENCE_ORDER=HTTP_X_REAL_IP,REMOTE_ADDR \
    LOG_LEVEL_PYTHON=INFO

# Root on purpose: the entrypoint chowns Railway's root-owned volume mounts
# and drops to the wger user (uid 1000) before starting nginx + gunicorn.
CMD ["/railway-entrypoint.sh"]
