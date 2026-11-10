#!/bin/bash
# Root stage of the Railway wrapper entrypoint.
# Railway mounts volumes as root:root; the image runs as wger (uid 1000).
# Fix ownership, then hand off to the user-stage script with the full env.
set -e

mkdir -p /home/wger/media /home/wger/static /home/wger/beat \
         /home/wger/nginx-temp/client_body /home/wger/nginx-temp/proxy \
         /home/wger/nginx-temp/fastcgi /home/wger/nginx-temp/uwsgi \
         /home/wger/nginx-temp/scgi
chown -R wger:wger /home/wger/media /home/wger/static /home/wger/beat /home/wger/nginx-temp

echo "[railway] ownership fixed, dropping to uid 1000"
exec gosu wger:wger /bin/bash /home/wger/railway-entry-user.sh
