package com.sl.devops.agent;

import java.lang.instrument.Instrumentation;

/**
 * Educational Java agent. It records that premain ran and prints JVM metadata.
 * It does not transform classes or alter application/licensing behavior.
 */
public final class ExampleAgent {
    private ExampleAgent() {}

    public static void premain(String options, Instrumentation instrumentation) {
        String safeOptions = options == null ? "" : options;
        System.setProperty("example.agent.loaded", "true");
        System.setProperty("example.agent.options", safeOptions);

        System.out.println("[example-agent] premain active");
        System.out.println("[example-agent] options=" + safeOptions);
        System.out.println("[example-agent] java.version=" + System.getProperty("java.version"));
        System.out.println("[example-agent] java.vendor=" + System.getProperty("java.vendor"));
        System.out.println("[example-agent] command=" + System.getProperty("sun.java.command", "unknown"));
        System.out.println("[example-agent] instrumentation=" + (instrumentation != null));
    }
}
