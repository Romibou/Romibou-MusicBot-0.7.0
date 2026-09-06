#!/bin/sh
set -eu

# --- Render port binding -----------------------------------------------
# Render's free Web Service tier requires the container to answer on a
# port, and puts it to sleep otherwise. This tiny responder (paired with
# UptimeRobot pinging the Render URL every 5 min) keeps the bot alive
# without needing any changes to the Java code.
PORT="${PORT:-10000}"
( socat TCP-LISTEN:"$PORT",fork,reuseaddr \
    SYSTEM:'printf "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"' \
    >/dev/null 2>&1 & )
echo "[INFO] HTTP keep-alive responder listening on port $PORT"
# -------------------------------------------------------------------------

# --- Render secret file -------------------------------------------------
if [ -f /etc/secrets/config.txt ]; then
  cp /etc/secrets/config.txt /musicbot/config.txt
  echo "[INFO] Loaded config.txt from Render secret file"
fi
# -------------------------------------------------------------------------


JAR="/app/app.jar"

if [ ! -f "$JAR" ]; then
  echo "[ERROR] JAR file not found at /app/app.jar"
  exit 1
fi

echo "[INFO] ========================================"
echo "[INFO] JMusicBot Containerized"
echo "[INFO] ========================================"
echo "[INFO] Selected jar: $JAR"
echo "[INFO] Working directory: $(pwd)"
if [ -f "config.txt" ]; then
  echo "[INFO] config.txt: Found (existing)"
else
  echo "[INFO] config.txt: Not found (will be generated on first run)"
fi
echo "[INFO] ========================================"

# Default JVM options for optimal audio performance (ZGC with sub-ms pauses)
# Set JAVA_OPTS to override; add -Xms/-Xmx for heap limits if desired
: "${JAVA_OPTS:=-XX:+UseZGC -XX:+AlwaysPreTouch}"

# Build argv
set -- java -Dnogui=true --enable-native-access=ALL-UNNAMED

# Append JAVA_OPTS (either default or user-provided)
if [ -n "${JAVA_OPTS:-}" ]; then
  # shellcheck disable=SC2086
  set -- "$@" $JAVA_OPTS
fi

set -- "$@" -jar "$JAR"

exec "$@"
