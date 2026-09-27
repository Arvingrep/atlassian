# Educational Java Agent

最小化 Java Instrumentation 示例，仅演示 `premain()` 和 JVM 启动参数，不修改应用类或授权逻辑。

## 构建与测试

```bash
example-agent/build.sh
example-agent/tests/test-agent.sh
```

输出：

```text
example-agent/build/example-agent.jar
```

Manifest：

```text
Premain-Class: com.sl.devops.agent.ExampleAgent
```

## 独立运行

```bash
docker build -t example-agent:local example-agent
docker run --rm example-agent:local
```

独立镜像通过以下参数加载 Agent：

```text
JAVA_TOOL_OPTIONS=-javaagent:/var/agent/example-agent.jar=environment=container
```

## Jira / Confluence

应用镜像中的路径：

```text
/var/agent/example-agent.jar
```

Atlassian 启动脚本会执行辅助 JVM，因此应用镜像使用：

```text
JVM_SUPPORT_RECOMMENDED_ARGS=-javaagent:/var/agent/example-agent.jar=application=...
```

检查：

```bash
scripts/check-java-agent.sh jira-9.6.0
scripts/check-java-agent.sh confluence-7.19.7
```

## 镜像

```text
ghcr.io/arvingrep/atlassian-example-agent:latest
ghcr.io/arvingrep/atlassian-jira:9.6.0-example-agent
ghcr.io/arvingrep/atlassian-confluence:7.19.7-example-agent
```

独立 Agent 镜像支持 `linux/amd64` 和 `linux/arm64`；旧版 Jira、Confluence 基础镜像仅支持 `linux/amd64`。
