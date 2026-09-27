ARG BASE_IMAGE=atlassian/confluence-server:7.19.7-jdk11

FROM eclipse-temurin:11-jdk AS agent-build
WORKDIR /workspace
COPY example-agent/src ./src
COPY example-agent/MANIFEST.MF ./MANIFEST.MF
RUN mkdir -p build/classes \
 && find src/main/java -name '*.java' -print0 | xargs -0 javac -source 11 -target 11 -d build/classes \
 && jar cfm build/example-agent.jar MANIFEST.MF -C build/classes .

FROM ${BASE_IMAGE}
LABEL org.opencontainers.image.title="Confluence with educational Java premain agent" \
      org.opencontainers.image.description="Confluence with a non-transforming Java instrumentation example"
USER root
RUN mkdir -p /var/agent
#COPY --from=agent-build /workspace/build/example-agent.jar /var/agent/example-agent.jar
COPY --from=agent-build /workspace/build/example-agent.jar /var/agent/example-agent.jar
RUN chown -R confluence:confluence /var/agent
ENV JVM_SUPPORT_RECOMMENDED_ARGS="-javaagent:/var/agent/example-agent.jar=application=confluence"
USER confluence
