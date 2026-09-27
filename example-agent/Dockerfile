FROM eclipse-temurin:11-jdk AS agent-build
WORKDIR /workspace
COPY src ./src
COPY MANIFEST.MF ./MANIFEST.MF
RUN mkdir -p build/classes \
 && find src/main/java -name '*.java' -print0 | xargs -0 javac -source 11 -target 11 -d build/classes \
 && jar cfm build/example-agent.jar MANIFEST.MF -C build/classes .

FROM eclipse-temurin:11-jre
COPY --from=agent-build /workspace/build/example-agent.jar /var/agent/example-agent.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/var/agent/example-agent.jar=environment=container"
CMD ["java", "-cp", "/var/agent/example-agent.jar", "com.sl.devops.agent.AgentSmokeMain"]
