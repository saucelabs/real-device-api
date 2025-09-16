# Faster, Smarter Appium Testing with RDC Access API Sessions

For testers, time is a critical resource. This guide demonstrates how to use the Sauce Labs Access API to use your devices more efficiently 
and decrease the runtime of your Appium test suite. This approach enables you to run more tests, get faster feedback, and gain greater 
control over your mobile testing workflow.

## The Test-per-Session Model vs. The Suite-per-Session Model

Think about a traditional Appium test run. For every single test, you typically have to:

**Traditional Model (Test-per-Session):**
1. Wait for a device to become available.
2. Wait for the device to be prepared.
3. Wait for the Appium session to start.
4. Run your test.
5. Tear down the session and release the device.
6. Repeat for every test in your suite.

This cycle means a lot of your pipeline's time is spent on repetitive setup and teardown, not on executing tests.

**The OpenAPI Session Model (Suite-per-Session):**

***The OpenAPI session model transforms this workflow.*** Instead of reserving a device for each individual Appium test, you reserve a 
device once for the entire suite. You can then run any number of tests on that single, persistent device session.

1. Start a device session
2. Start Appium server once.
3. Run Test 1.
4. Run Test 2.
5. ...Run Test N
6. Tear down the session once.


## Core Value for Testers: Speed, Control, and Efficiency

### Accelerate Your Test Suite Execution
By paying the "startup cost" of getting a device and launching Appium only once, your subsequent tests become faster.

* ***Eliminate Redundant Waits:*** No more waiting for a new device for each test. The device is yours for the duration of
  the test suite.

* ***Instant Test Execution:*** Your second, third, and fourth tests can start immediately after the previous one finishes.
  This drastically shortens the feedback loop, allowing you to find—and verify fixes for—bugs faster than ever before.

### Unprecedented Control: Become a Device Orchestrator
An open session transforms the remote device into your personal workbench. You are no longer just running a test;
you are orchestrating the device's state to create more powerful and realistic test scenarios.

* ***Run Dependent Tests:*** Easily test workflows that span multiple steps, like adding an item to a cart in one test and
  checking out in another, all without restarting the app.

* ***Manipulate Device State:*** Between tests, you have full control. You can programmatically:
  * Push test data, files, or pre-configured settings.
  * Clear app cache or user data to start the next test from a clean slate.
  * Run diagnostic scripts.

* ***Debug with Precision:*** If a test fails, the device and app remain in their failed state. You can keep the session
  open, get the Live View URL, and manually inspect the device to understand exactly what went wrong.

### Centralizing Session Management

Running an entire test suite on a single device session introduces a new lifecycle to manage. A recommended pattern, shown in the example 
below, is to centralize the device and Appium setup logic using a suite-level setup method (like JUnit 5's `@BeforeAll`).

This isolates the infrastructure management—reserving the device and starting Appium—from the test logic. As a result, 
the individual `@Test` methods can be written to focus purely on application interactions, operating on the assumption 
that an active session is already available.

## How It Looks in Practice
This modern Java and JUnit 5 example shows how elegantly this concept translates to code.

```java
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
	 * Waits for a session to reach an expected state
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
	 * Actual Appium test.
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
    // ... Helper Methods
}
```

***Note on Running the Example:***
To run this code, save it as `OpenApiAppiumTest.java`, set your `SAUCE_USERNAME` and `SAUCE_API_KEY` environment variables, then compile 
with `javac OpenApiAppiumTest.java` and execute with `java OpenApiAppiumTest`.

For a complete runnable example (including all helper methods), check out our [Java sample](./samples/java/tests/OpenApiAppiumTest.java).