ARG BASE_IMAGE=atlassian/jira-software:9.6.0-jdk11
FROM ${BASE_IMAGE}
USER root
RUN mkdir -p /var/agent
COPY example-agent.jar /var/agent/example-agent.jar
RUN chown -R jira:jira /var/agent
ENV JVM_SUPPORT_RECOMMENDED_ARGS="-javaagent:/var/agent/example-agent.jar=application=jira"
USER jira
