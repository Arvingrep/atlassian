package com.sl.devops.agent;

/** Simple executable used by CI to prove premain executes before main. */
public final class AgentSmokeMain {
    private AgentSmokeMain() {}

    public static void main(String[] args) {
        System.out.println("agent.loaded=" + System.getProperty("example.agent.loaded", "false"));
        System.out.println("agent.options=" + System.getProperty("example.agent.options", ""));
    }
}
