#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

for spec in "jira:jira-software:jira" "confluence:confluence-server:confluence"; do
  IFS=: read -r directory product user <<<"${spec}"
  file="${ROOT}/${directory}/Dockerfile"

  grep -Fq "ARG BASE_IMAGE=atlassian/${product}:" "${file}"
  grep -Fq 'COPY --from=agent-build /workspace/build/example-agent.jar /var/agent/example-agent.jar' "${file}"
  grep -Fq "chown -R ${user}:${user} /var/agent" "${file}"
  grep -Fq 'JVM_SUPPORT_RECOMMENDED_ARGS="-javaagent:/var/agent/example-agent.jar' "${file}"

  if grep -Eq 'haxqer|atlassian-agent\.jar|AGENT_VERSION' "${file}"; then
    echo "${file} still contains the legacy licensing agent" >&2
    exit 1
  fi
done
