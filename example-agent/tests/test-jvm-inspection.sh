#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="${ROOT}/scripts/check-java-agent.sh"

output=$("${SCRIPT}" jira-9.6.0)
printf '%s\n' "${output}"
grep -Fq 'JAVA_TOOL_OPTIONS=' <<<"${output}"
grep -Fq 'JVM command line:' <<<"${output}"
