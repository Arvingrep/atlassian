#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

for dockerfile in Dockerfile.jira Dockerfile.confluence; do
  file="${ROOT}/example-agent/${dockerfile}"
  grep -Fq 'JVM_SUPPORT_RECOMMENDED_ARGS="-javaagent:/var/agent/example-agent.jar' "${file}"
  if grep -Fq 'ENV JAVA_TOOL_OPTIONS=' "${file}"; then
    echo "${dockerfile} must not apply JAVA_TOOL_OPTIONS to Atlassian launcher helper JVMs" >&2
    exit 1
  fi
done
