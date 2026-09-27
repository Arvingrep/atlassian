#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
AGENT_DIR="${ROOT}/example-agent"
JAR="${AGENT_DIR}/build/example-agent.jar"

"${AGENT_DIR}/build.sh"

test -f "${JAR}"
unzip -p "${JAR}" META-INF/MANIFEST.MF | grep -Fq 'Premain-Class: com.sl.devops.agent.ExampleAgent'

output=$(docker run --rm \
  -v "${JAR}:/var/agent/example-agent.jar:ro" \
  -e 'JAVA_TOOL_OPTIONS=-javaagent:/var/agent/example-agent.jar=environment=smoke' \
  eclipse-temurin:11-jre \
  java -cp /var/agent/example-agent.jar com.sl.devops.agent.AgentSmokeMain)

printf '%s\n' "${output}"
grep -Fq '[example-agent] premain active' <<<"${output}"
grep -Fq '[example-agent] options=environment=smoke' <<<"${output}"
grep -Fq 'agent.loaded=true' <<<"${output}"
grep -Fq 'agent.options=environment=smoke' <<<"${output}"
