# Educational Java Agent

This is a minimal, non-transforming Java instrumentation agent. It demonstrates
how `premain` executes before an application's `main` method, records two system
properties, and prints basic JVM metadata. It does not modify classes, product
behavior, or licensing.

## Build and test

No host JDK is required; compilation runs inside `eclipse-temurin:11-jdk`:

```bash
example-agent/build.sh
example-agent/tests/test-agent.sh
```

The JAR is created at:

```text
example-agent/build/example-agent.jar
```

Its manifest declares:

```text
Premain-Class: com.sl.devops.agent.ExampleAgent
```

## `JAVA_TOOL_OPTIONS` demonstration

The standalone smoke test uses:

```bash
JAVA_TOOL_OPTIONS=-javaagent:/var/agent/example-agent.jar=environment=smoke
```

The JVM loads `ExampleAgent.premain(...)` before `AgentSmokeMain.main(...)`.
The agent then exposes:

```text
example.agent.loaded=true
example.agent.options=environment=smoke
```

## Jira and Confluence images

Build and start the demonstration images with the two Compose files:

```bash
docker compose --env-file .env.versions \
  -f docker-compose.migration.yml \
  -f docker-compose.agent-demo.yml \
  build jira confluence

docker compose --env-file .env.versions \
  -f docker-compose.migration.yml \
  -f docker-compose.agent-demo.yml \
  up -d
```

The active local build definitions are `jira/Dockerfile` and
`confluence/Dockerfile`; the Compose override references those files directly.
The resulting containers contain:

```text
/var/agent/example-agent.jar
```

For Atlassian applications, the derived images use
`JVM_SUPPORT_RECOMMENDED_ARGS` rather than global `JAVA_TOOL_OPTIONS`.
`JAVA_TOOL_OPTIONS` also affects helper Java processes used by Atlassian startup
scripts and can corrupt their version/output parsing. The standalone image still
demonstrates `JAVA_TOOL_OPTIONS`; the application images inject `-javaagent`
only into the main Tomcat JVM.

Inspect the effective environment, JVM command line, and JAR:

```bash
scripts/check-java-agent.sh jira-9.6.0
scripts/check-java-agent.sh confluence-7.19.7
```

## Multi-platform CI

The `Example Java agent` GitHub workflow:

- tests the JAR and verifies `premain` runs before `main`;
- uploads the compiled JAR as a workflow artifact;
- builds the standalone demonstration image for `linux/amd64` and
  `linux/arm64`; and
- builds the Jira and Confluence demonstration images for `linux/amd64`.

The old Jira 9.6.0 and Confluence 7.19.7 base images are amd64 images, so their
derived images cannot honestly be published as native arm64 images. The agent
itself and its standalone Java 11 image are multi-platform.
