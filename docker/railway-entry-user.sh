#!/bin/bash
# User stage (wger, uid 1000). Boot order mirrors the upstream entrypoint
# (extras/docker/production/entrypoint.sh at the pinned image digest), with
# two inserted steps: JWT keypair handling and the admin password seed.
set -e
cd /home/wger/src

# ---- 1. JWT keypair: generate once, persist on the media volume ----
# Required for API token auth (SimpleJWT / allauth.headless); unset keys only
# warn at settings import but break token issuing.
if [ ! -s /home/wger/media/jwt-keys.env ]; then
    echo "[railway] generating fresh JWT keypair"
    python3 manage.py generate-jwt-keys 2>/dev/null | grep '^JWT_' > /home/wger/media/jwt-keys.env
fi
if ! grep -q '^JWT_PRIVATE_KEY=' /home/wger/media/jwt-keys.env; then
    echo "[railway] JWT key file is corrupt, regenerating"
    python3 manage.py generate-jwt-keys 2>/dev/null | grep '^JWT_' > /home/wger/media/jwt-keys.env
fi
set -a
. /home/wger/media/jwt-keys.env
set +a
echo "[railway] JWT keypair loaded"

# ---- 2. nginx: serves /static/ + /media/, proxies / to gunicorn ----
# Railway injects PORT at runtime once a domain exists; render the listen
# port accordingly (fallback 8080 = the pinned domain targetPort).
LISTEN_PORT="${WGER_LISTEN_PORT:-${PORT:-8080}}"
sed "s/__WGER_LISTEN__/${LISTEN_PORT}/" /etc/nginx/railway.conf > /home/wger/nginx-temp/nginx.conf
nginx -c /home/wger/nginx-temp/nginx.conf
sleep 1
if ! pgrep -x nginx > /dev/null; then
    echo "[railway] nginx failed to start, not starting the server"
    exit 1
fi
echo "[railway] nginx listening on port ${LISTEN_PORT}"

# ---- 3. Bootstrap: on an empty DB run migrate + bundled fixtures + admin ----
# (upstream behavior; fails hard when the database is not reachable yet)
if ! wger bootstrap --no-process-static; then
    echo "[railway] bootstrapping the application failed, not starting the server"
    exit 1
fi
echo "[railway] bootstrap done (fixtures + admin ensured)"

# ---- 4. collectstatic (production mode) ----
clear_static=""
if [[ "${DJANGO_CLEAR_STATIC_FIRST:-False}" == "True" ]]; then
    clear_static="--clear"
fi
if [[ "$DJANGO_DEBUG" == "False" && "${DJANGO_COLLECTSTATIC_ON_STARTUP:-True}" == "True" ]]; then
    echo "[railway] running collectstatic"
    python3 manage.py collectstatic --no-input $clear_static
fi

# ---- 5. Database migrations ----
if [[ "${DJANGO_PERFORM_MIGRATIONS:-True}" == "True" ]]; then
    echo "[railway] performing database migrations"
    if ! python3 manage.py migrate; then
        echo "[railway] database migrations failed, not starting the server"
        exit 1
    fi
fi

# ---- 6. Optional synchronous startup syncs (off by default on Railway) ----
if [[ "$SYNC_EXERCISES_ON_STARTUP" == "True" ]]; then
    echo "[railway] synchronizing exercises"
    python3 manage.py sync-exercises
fi
if [[ "$DOWNLOAD_EXERCISE_IMAGES_ON_STARTUP" == "True" ]]; then
    echo "[railway] downloading exercise images"
    python3 manage.py download-exercise-images
fi
if [[ "$DOWNLOAD_EXERCISE_VIDEOS_ON_STARTUP" == "True" ]]; then
    echo "[railway] downloading exercise videos"
    python3 manage.py download-exercise-videos
fi

# ---- 7. Seed the admin password (Railway-specific step) ----
# The upstream image creates admin/adminadmin via the users.json fixture on
# first boot. While the admin still carries that default password, replace it
# with WGER_ADMIN_PASSWORD (per-deploy generated secret). A password the user
# changed themselves is never overwritten.
python3 manage.py shell <<'PYEOF'
import os
from django.contrib.auth.models import User

u = User.objects.filter(username='admin').first()
pw = os.environ.get('WGER_ADMIN_PASSWORD', '')
if u and pw and u.check_password('adminadmin'):
    u.set_password(pw)
    u.save()
    print('[railway] admin password seeded from WGER_ADMIN_PASSWORD')
else:
    print('[railway] admin password left untouched (changed by user or variable missing)')
PYEOF

# ---- 8. Site URL ----
python3 manage.py set-site-url || echo "[railway] WARN: set-site-url skipped (SITE_URL unset or invalid)"

# ---- 9. Gunicorn ----
echo "[railway] starting gunicorn on port ${WGER_PORT:-8000}"
exec gunicorn wger.wsgi:application --preload --bind 0.0.0.0:${WGER_PORT:-8000}
