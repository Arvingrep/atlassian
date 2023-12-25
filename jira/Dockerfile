FROM openjdk:11.0
LABEL maintainer="haxqer <haxqer666@gmail.com>" version="8.7.1"

# ATLASSIAN_PRODUCTION: jira-software jira-core
ARG APP_NAME=jira-software
ARG APP_VERSION=8.7.1
ARG AGENT_VERSION=1.2.2
ARG MYSQL_DRIVER_VERSION=5.1.48

ENV JIRA_USER=jira \
    JIRA_GROUP=jira \
    JIRA_HOME=/var/jira \
    JIRA_INSTALL=/opt/jira \
    JVM_MINIMUM_MEMORY=1g \
    JVM_MAXIMUM_MEMORY=3g \
    JVM_CODE_CACHE_ARGS='-XX:InitialCodeCacheSize=1g -XX:ReservedCodeCacheSize=2g' \
    AGENT_PATH=/var/agent \
    AGENT_FILENAME=atlassian-agent.jar

# 设置启动加载代理包
# RUN echo 'export CATALINA_OPTS="-javaagent:${AGENT_PATH}/${AGENT_FILENAME} ${CATALINA_OPTS}"' >> ${JIRA_INSTALL}/bin/setenv.sh
ENV JAVA_OPTS="-javaagent:${AGENT_PATH}/${AGENT_FILENAME} ${JAVA_OPTS}"

RUN mkdir -p ${JIRA_INSTALL} ${JIRA_HOME} ${AGENT_PATH} \
&& curl -o ${AGENT_PATH}/${AGENT_FILENAME}  https://github.com/haxqer/jira/releases/download/v${AGENT_VERSION}/atlassian-agent.jar -L \
&& curl -o /tmp/atlassian.tar.gz https://product-downloads.atlassian.com/software/jira/downloads/atlassian-${APP_NAME}-${APP_VERSION}.tar.gz -L \
&& tar xzf /tmp/atlassian.tar.gz -C /opt/jira/ --strip-components 1 \
&& rm -f /tmp/atlassian.tar.gz \
&& curl -o /opt/jira/lib/mysql-connector-java-${MYSQL_DRIVER_VERSION}.jar https://repo1.maven.org/maven2/mysql/mysql-connector-java/${MYSQL_DRIVER_VERSION}/mysql-connector-java-${MYSQL_DRIVER_VERSION}.jar -L \
&& echo "jira.home = ${JIRA_HOME}" > ${JIRA_INSTALL}/atlassian-jira/WEB-INF/classes/jira-application.properties

RUN export CONTAINER_USER=$JIRA_USER \
&& export CONTAINER_GROUP=$JIRA_GROUP \
&& groupadd -r $JIRA_GROUP && useradd -r -g $JIRA_GROUP $JIRA_USER \
&& chown -R $JIRA_USER:$JIRA_GROUP ${JIRA_INSTALL} ${JIRA_HOME}/

VOLUME $JIRA_HOME
USER $JIRA_USER
WORKDIR $JIRA_INSTALL
EXPOSE 8080

ENTRYPOINT ["/opt/jira/bin/start-jira.sh", "-fg"]
