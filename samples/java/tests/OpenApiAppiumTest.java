import java.io.IOException;
import java.net.URI;
import java.net.URL;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Base64;

public class OpenApiAppiumTest {
	// Fetches credentials from environment variables
	private static final String SAUCE_USERNAME = System.getenv("SAUCE_USERNAME");
	private static final String SAUCE_API_KEY = System.getenv("SAUCE_API_KEY");

	// Base URL for the Sauce Labs RDC API - Using US-WEST
	private static final String BASE_URL = "https://api.us-west-1.saucelabs.com/rdc/v2/";

	private static final HttpClient client = HttpClient.newBuilder()
			.version(HttpClient.Version.HTTP_2)
			.connectTimeout(Duration.ofSeconds(20))
			.build();

	public enum ApiSessionState { PENDING, CREATING, ACTIVE, CLOSING, CLOSED, ERRORED }

	/**
	 * Main entry point for the script.
	 */
	public static void main(String[] args) throws IOException, InterruptedException {
		// Basic validation for credentials
		if (SAUCE_USERNAME == null || SAUCE_API_KEY == null || SAUCE_USERNAME.isEmpty() || SAUCE_API_KEY.isEmpty()) {
			System.err.println("Error: Please set SAUCE_USERNAME and SAUCE_API_KEY environment variables.");
			return;
		}

		System.out.println("--- Starting API Session Demo ---");
		String sessionId = null;
		try {
			// 1. Create a session for an Android device
			sessionId = createApiSession("Android");
			System.out.println("Successfully created session. ID: " + sessionId);

			// 2. Wait for the session to become active
			waitForApiSessionState(sessionId, ApiSessionState.ACTIVE, 3);
			System.out.println("Session is now ACTIVE.");

			// 3. Start the Appium server for the active session
			var appiumUrl = startAppiumServer(sessionId);

			// 4. At this point, you would run your Appium tests
			runSimpleAppiumTest(appiumUrl);

		} catch (Exception e) {
			System.err.println("An error occurred during the session lifecycle: " + e.getMessage());
			e.printStackTrace();
		} finally {
			// 5. Ensure the session is always closed
			if (sessionId != null) {
				System.out.println("--- Closing Session ---");
				closeApiSession(sessionId);
				System.out.println("Session marked for closing. Waiting for confirmation...");
				waitForApiSessionState(sessionId, ApiSessionState.CLOSED, 1);
				System.out.println("Session is confirmed CLOSED.");
			}
		}
	}

	/**
	 * Creates a new API session.
	 * POST /sessions
	 */
	private static String createApiSession(String os) throws IOException, InterruptedException {
		String requestBody = String.format("""
                {
                  "device": {
                     "os": "%s"
                  }
                }
                """, os);

		HttpRequest request = buildRequest("/sessions", "POST", requestBody);
		HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

		if (response.statusCode() != 200) {
			System.out.println(response);
			throw new RuntimeException("Failed to create session. Status: " + response.statusCode() + " Body: " + response.body());
		}

		return parseJsonValue(response.body(), "id");
	}

	/**
	 * Starts the Appium server for a given session.
	 * POST /sessions/{sessionId}/appiumserver
	 */
	private static URL startAppiumServer(String sessionId) throws IOException, InterruptedException {
		String requestBody = """
                { "appiumVersion": "latest" }
                """;

		HttpRequest request = buildRequest("/sessions/" + sessionId + "/appiumserver", "POST", requestBody);
		HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

		if (response.statusCode() != 200) {
			throw new RuntimeException("Failed to start Appium server. Status: " + response.statusCode() + " Body: " + response.body());
		}

		return new URL(parseJsonValue(response.body(), "url"));
	}

	/**
	 * Closes an active API session.
	 * DELETE /sessions/{sessionId}
	 */
	private static void closeApiSession(String sessionId) throws IOException, InterruptedException {
		HttpRequest request = buildRequest("/sessions/" + sessionId, "DELETE", null);
		HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

		if (response.statusCode() != 200) {
			System.err.println("Warning: Failed to close session gracefully. Status: " + response.statusCode() + " Body: " + response.body());
		}
	}

	/**
	 * Retrieves the current state of a session.
	 * GET /sessions/{sessionId}
	 */
	private static ApiSessionState getApiSessionState(String sessionId) throws IOException, InterruptedException {
		HttpRequest request = buildRequest("/sessions/" + sessionId, "GET", null);
		HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

		if (response.statusCode() != 200) {
			throw new RuntimeException("Failed to get session state. Status: " + response.statusCode() + " Body: " + response.body());
		}

		String stateStr = parseJsonValue(response.body(), "state");
		return ApiSessionState.valueOf(stateStr);
	}

	/**
	 * Waits for a session to reach an expected state by polling.
	 */
	private static void waitForApiSessionState(String sessionId, ApiSessionState expectedState, int timeoutMinutes) throws IOException, InterruptedException {
		System.out.printf("Waiting for session to become %s (timeout: %d minutes)...%n", expectedState, timeoutMinutes);
		long timeoutMillis = System.currentTimeMillis() + Duration.ofMinutes(timeoutMinutes).toMillis();
		long pollIntervalMillis = 5000;

		while (System.currentTimeMillis() < timeoutMillis) {
			ApiSessionState currentState = getApiSessionState(sessionId);
			System.out.println("   Current state: " + currentState);
			if (currentState == expectedState) {
				return;
			}
			Thread.sleep(pollIntervalMillis);
		}

		throw new RuntimeException("Timeout: Session did not transition to " + expectedState + " within " + timeoutMinutes + " minutes.");
	}

	/**
	 * Placeholder for where the actual Appium test logic would go.
	 */
	private static void runSimpleAppiumTest(URL appiumURL) {
		System.out.println("--- Appium Test Simulation ---");
		System.out.println("    This is where you would initialize your Appium Driver and run tests.");
		System.out.println("    Connect to the Appium URL: " + appiumURL);
		System.out.println("""
                    Example test setup:
                    MutableCapabilities caps = new MutableCapabilities();
                    // ... add your capabilities ...
                    AndroidDriver driver = new AndroidDriver(appiumURL, caps);
                    // ... driver.get(...), driver.findElement(...), etc. ...
                    driver.quit();
            """);
		System.out.println("Appium test simulation complete.");
	}

	// --- UTILITY METHODS ---

	/**
	 * A helper to build an HttpRequest with common settings (Auth, Headers).
	 */
	private static HttpRequest buildRequest(String path, String method, String body) {
		String credentials = Base64.getEncoder().encodeToString((SAUCE_USERNAME + ":" + SAUCE_API_KEY).getBytes());
		HttpRequest.BodyPublisher bodyPublisher = (body != null && !body.isEmpty())
				? HttpRequest.BodyPublishers.ofString(body)
				: HttpRequest.BodyPublishers.noBody();

		return HttpRequest.newBuilder()
				.uri(URI.create(BASE_URL + path))
				.header("Authorization", "Basic " + credentials)
				.header("Content-Type", "application/json")
				.method(method, bodyPublisher)
				.build();
	}

	/**
	 * A very simple parser to extract a value from a JSON string without a library.
	 * Assumes the key is unique and the value is a simple string.
	 */
	private static String parseJsonValue(String json, String key) {
		String keyPattern = "\"" + key + "\":\"";
		int startIndex = json.indexOf(keyPattern) + keyPattern.length();
		if (startIndex < keyPattern.length()) {
			throw new RuntimeException("Key '" + key + "' not found in JSON response: " + json);
		}
		int endIndex = json.indexOf("\"", startIndex);
		return json.substring(startIndex, endIndex);
	}
}