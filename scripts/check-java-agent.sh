#!/usr/bin/env bash
set -euo pipefail

container=${1:?usage: check-java-agent.sh CONTAINER}

echo "Container: ${container}"
echo "JAVA_TOOL_OPTIONS=$(docker exec "${container}" sh -c 'printf %s "${JAVA_TOOL_OPTIONS:-}"')"
echo "JVM_SUPPORT_RECOMMENDED_ARGS=$(docker exec "${container}" sh -c 'printf %s "${JVM_SUPPORT_RECOMMENDED_ARGS:-}"')"
echo "JVM command line:"
docker exec "${container}" sh -c 'ps -ef | grep "[j]ava"'
echo "Agent file:"
docker exec "${container}" sh -c '
  if [ -f /var/agent/example-agent.jar ]; then
    ls -l /var/agent/example-agent.jar
  else
    echo "/var/agent/example-agent.jar is not installed"
  fi
'
