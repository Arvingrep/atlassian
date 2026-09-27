#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
rm -rf "${ROOT}/build/classes"
mkdir -p "${ROOT}/build/classes"

docker run --rm \
  -v "${ROOT}:/workspace" \
  -w /workspace \
  eclipse-temurin:11-jdk \
  bash -ec '
    find src/main/java -name "*.java" -print0 | xargs -0 javac -source 11 -target 11 -d build/classes
    jar cfm build/example-agent.jar MANIFEST.MF -C build/classes .
  '

echo "Built ${ROOT}/build/example-agent.jar"
