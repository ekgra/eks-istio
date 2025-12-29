#!/bin/sh
set -e

# Toggle debug with env:
#   DEBUG=true
#   DEBUG_PORT=5005 (default)
#   DEBUG_SUSPEND=y|n (default n)
DEBUG_PORT="${DEBUG_PORT:-5005}"
DEBUG_SUSPEND="${DEBUG_SUSPEND:-n}"

JAVA_OPTS="${JAVA_OPTS:-}"

if [ "${DEBUG:-false}" = "true" ]; then
  # JDWP remote debug (works well inside Docker)
  JAVA_OPTS="$JAVA_OPTS -agentlib:jdwp=transport=dt_socket,server=y,suspend=${DEBUG_SUSPEND},address=*:${DEBUG_PORT}"
  echo "JDWP debug enabled on port ${DEBUG_PORT} (suspend=${DEBUG_SUSPEND})"
fi

exec java $JAVA_OPTS -jar /app/app.jar
