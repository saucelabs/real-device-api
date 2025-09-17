package com.demo.api;

import org.json.JSONObject;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.net.URI;
import java.net.URL;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Base64;

import io.appium.java_client.android.AndroidDriver;

import org.openqa.selenium.MutableCapabilities;

public class DemoAppiumTest {

	private static String sessionId; // The ID for our reserved device session
	private static URL appiumUrl;    // The Appium URL, reused for all tests

	private static String BASE_URL = "https://api.us-west-1.saucelabs.com";
	private static String SAUCE_USERNAME = "username";
	private static String SAUCE_ACCESS_KEY = "access_key";

	private static final HttpClient client = HttpClient.newBuilder()
			.version(HttpClient.Version.HTTP_2)
			.connectTimeout(Duration.ofSeconds(20))
			.build();
	/**
	 * This method reserves a device via the Sauce Labs  Access API and starts a persistent Appium server for that device.
	 *
	 * The resulting session ID and Appium URL are stored for all subsequent tests.
	 *
	 * Runs once before any @Test methods.
	 */
	@BeforeAll
	public static void setupSuite() throws Exception  {
		var createSessionRequestBody = """
            { "device": { "os": "android" }  }
            """;

		var createSessionResponse = POST("/rdc/v2/sessions", createSessionRequestBody);
		System.out.println("response: " + createSessionResponse);
		sessionId = createSessionResponse.getString("id");

		waitForSessionToBeActive(sessionId);

		var startAppiumServerRequestBody = """
            { "appiumVersion": "latest" }
            """;
		var startAppiumServerResponse = POST("/rdc/v2/sessions/%s/appiumserver".formatted(sessionId), startAppiumServerRequestBody);
		appiumUrl = new URL(startAppiumServerResponse.getString("url"));
	}

	/**
	 * The FINAL cleanup. This releases the device after all tests are done.
	 */
	@AfterAll
	public static void tearDownSuite() throws IOException, InterruptedException {
		if (sessionId != null) {
			System.out.println("Releasing Device Session: " + sessionId);
			var closeSessionResponse = DELETE("/rdc/v2/sessions/" + sessionId);
		}
	}

	// --- Rapid-Fire Tests ---
	// Each of these methods runs back-to-back on the SAME device.

	@Test
	public void first_test() {
		System.out.println("Executing first test");
		var capabilities = new MutableCapabilities();
		var driver = new AndroidDriver(appiumUrl, capabilities);

		try {
			driver.get("https://www.saucelabs.com");
		} finally {
			// This quits the Appium client connection for this specific test.
			// The underlying device session remains active for the next test.
			driver.quit();
		}
	}

	@Test
	public void second_test() {
		System.out.println("Executing second test");
		var capabilities = new MutableCapabilities();
		var driver = new AndroidDriver(appiumUrl, capabilities);

		try {
			driver.get("https://www.youtube.com");
		} finally {
			// This quits the Appium client connection for this specific test.
			// The underlying device session remains active for the next test.
			driver.quit();
		}
	}



	// ... Helper methods
	private static void waitForSessionToBeActive(String sessionId) throws Exception {
		System.out.println("Waiting for session active...");
		for (int i = 0; i < 5; i++) {
			var getSessionResponse = GET("/rdc/v2/sessions/" + sessionId);
			var currentState = getSessionResponse.getString("state");
			System.out.println("Current state: " + currentState + " Session info: " + getSessionResponse);

			if ("ACTIVE".equals(currentState)) {
				System.out.println("Session is now ACTIVE. Exiting loop.");
				return;
			}

			System.out.println("Waiting for 5 seconds...");
			Thread.sleep(5000); // sleep 5 seconds
		}
		throw new Exception("Session did not become active");
	}

	private static JSONObject POST(String apiUrl, String requestBody) throws IOException, InterruptedException {
		String credentials = SAUCE_USERNAME + ":" + SAUCE_ACCESS_KEY;
		String encodedAuth = Base64.getEncoder().encodeToString(credentials.getBytes());

		var request = HttpRequest.newBuilder()
				.uri(URI.create(BASE_URL + apiUrl))
				.header("Authorization", "Basic " + encodedAuth)
				.header("Content-Type", "application/json")
				.POST(HttpRequest.BodyPublishers.ofString(requestBody))
				.build();

		HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

		String responseBody = response.body();
		return new JSONObject(responseBody);
	}

	private static JSONObject GET(String apiUrl) throws IOException, InterruptedException {
		String credentials = SAUCE_USERNAME + ":" + SAUCE_ACCESS_KEY;
		String encodedAuth = Base64.getEncoder().encodeToString(credentials.getBytes());

		var request = HttpRequest.newBuilder()
				.uri(URI.create(BASE_URL + apiUrl))
				.header("Authorization", "Basic " + encodedAuth)
				.GET()
				.build();

		HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

		String responseBody = response.body();
		return new JSONObject(responseBody);
	}

	private static JSONObject DELETE(String apiUrl) throws IOException, InterruptedException {
		String credentials = SAUCE_USERNAME + ":" + SAUCE_ACCESS_KEY;
		String encodedAuth = Base64.getEncoder().encodeToString(credentials.getBytes());

		var request = HttpRequest.newBuilder()
				.uri(URI.create(BASE_URL + apiUrl))
				.header("Authorization", "Basic " + encodedAuth)
				.DELETE()
				.build();

		HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

		String responseBody = response.body();
		return new JSONObject(responseBody);
	}

}