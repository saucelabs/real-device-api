package com.saucelabs.rdc.openapi.helpers;

public class Env {

	public static final String ENVIRONMENT = "ENVIRONMENT";
	public static final String SAUCE_USERNAME = "SAUCE_USERNAME";
	public static final String ACCESS_KEY = "SAUCE_ACCESS_KEY";

	public static String getEnvironment() {
		return getEnvOrFail(ENVIRONMENT);
	}

	public static String getBaseURL() {
		return String.format("https://api.%s.saucelabs.com/rdc/v2/", getEnvironment());
	}

	public static String getSauceUsername() {
		return getEnvOrFail(SAUCE_USERNAME);
	}

	public static String getAccessKey() {
		return getEnvOrFail(ACCESS_KEY);
	}

	public static String getEnvOrFail(String env) {
		String value = System.getenv(env);
		if (value == null || value.isBlank()) {
			throw new IllegalStateException("Missing required environment variable: " + env);
		}
		return value;
	}
}
