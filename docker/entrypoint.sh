#!/bin/sh
set -eu

# --- Render port binding -----------------------------------------------
PORT="${PORT:-10000}"
socat TCP-LISTEN:"$PORT",bind=0.0.0.0,fork,reuseaddr \
    SYSTEM:'printf "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"' \
    >/tmp/socat.log 2>&1 &
SOCAT_PID=$!
sleep 2
if echo -n "" | socat -T2 - TCP:127.0.0.1:"$PORT" >/tmp/socat_test.log 2>&1; then
  echo "[INFO] HTTP keep-alive responder CONFIRMED listening on 0.0.0.0:$PORT (pid $SOCAT_PID)"
else
  echo "[WARN] HTTP keep-alive responder NOT reachable on port $PORT (pid $SOCAT_PID may be a zombie)"
  echo "[WARN] --- socat startup log ---"
  cat /tmp/socat.log 2>/dev/null || echo "[WARN] (empty)"
  echo "[WARN] --- connection test output ---"
  cat /tmp/socat_test.log 2>/dev/null || echo "[WARN] (empty)"
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
