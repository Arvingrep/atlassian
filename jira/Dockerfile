ARG BASE_IMAGE=atlassian/jira-software:9.6.0-jdk11

FROM eclipse-temurin:11-jdk AS agent-build
WORKDIR /workspace
COPY example-agent/src ./src
COPY example-agent/MANIFEST.MF ./MANIFEST.MF
RUN mkdir -p build/classes \
 && find src/main/java -name '*.java' -print0 | xargs -0 javac -source 11 -target 11 -d build/classes \
 && jar cfm build/example-agent.jar MANIFEST.MF -C build/classes .

FROM ${BASE_IMAGE}
LABEL org.opencontainers.image.title="Jira with educational Java premain agent" \
      org.opencontainers.image.description="Jira Software with a non-transforming Java instrumentation example"
USER root
RUN mkdir -p /var/agent
#COPY --from=agent-build /workspace/build/example-agent.jar /var/agent/example-agent.jar
COPY --from=agent-build /workspace/build/atlassian-agent.jar /var/agent/example-agent.jar
RUN chown -R jira:jira /var/agent
ENV JVM_SUPPORT_RECOMMENDED_ARGS="-javaagent:/var/agent/example-agent.jar=application=jira"
USER jira
