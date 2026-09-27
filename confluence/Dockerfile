ARG BASE_IMAGE=atlassian/confluence-server:7.19.7-jdk11
FROM ${BASE_IMAGE}
USER root
RUN mkdir -p /var/agent
COPY  example-agent.jar /var/agent/example-agent.jar
RUN chown -R confluence:confluence /var/agent
ENV JVM_SUPPORT_RECOMMENDED_ARGS="-javaagent:/var/agent/example-agent.jar=application=confluence"
USER confluence
