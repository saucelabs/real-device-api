package com.saucelabs.rdc.openapi.tests;

import static com.saucelabs.rdc.openapi.helpers.Env.getAccessKey;
import static com.saucelabs.rdc.openapi.helpers.Env.getBaseURL;
import static com.saucelabs.rdc.openapi.helpers.Env.getSauceUsername;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static io.restassured.RestAssured.given;

import com.saucelabs.rdc.openapi.model.ApiSessionState;

import org.awaitility.Awaitility;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.openqa.selenium.MutableCapabilities;
import org.openqa.selenium.OutputType;

import java.net.MalformedURLException;
import java.net.URL;
import java.util.Base64;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import io.appium.java_client.android.AndroidDriver;
import io.restassured.RestAssured;
import io.restassured.path.json.JsonPath;
import lombok.extern.slf4j.Slf4j;

@Slf4j
public class OpenApiAppiumTest {

	// A default timeout for state transitions can be defined here
	private static final long DEFAULT_TIMEOUT_MINUTES = 3;

	@BeforeAll
	public static void setup() {
		// Get test config from environment variables
		String username = getSauceUsername();
		String accessKey = getAccessKey();
		RestAssured.baseURI = getBaseURL();

		if (username == null || accessKey == null) {
			throw new IllegalArgumentException("Username and Access Key must be provided.");
		}

		RestAssured.authentication = RestAssured.basic(username, accessKey);
	}

	@Test
	public void test_android_simple_appium_test() throws MalformedURLException, InterruptedException {
		log.info("Starting Android session lifecycle test");
		String sessionId = createApiSession("Android");

		try {
			log.info("Created new Android session with ID: {}", sessionId);
			waitForApiSessionState(sessionId, ApiSessionState.ACTIVE, DEFAULT_TIMEOUT_MINUTES, TimeUnit.MINUTES);

			log.info("Verifying session {} is ACTIVE", sessionId);
			verifyApiSessionState(sessionId, ApiSessionState.ACTIVE);

			// Start the Appium server and get the URL
			String appiumUrl = startAppiumServer(sessionId);

			runSimpleAppiumAndroidTest(new URL(appiumUrl));
		} finally {
			log.info("Closing session: {}", sessionId);
			closeApiSession(sessionId);
			waitForApiSessionState(sessionId, ApiSessionState.CLOSED, 1, TimeUnit.MINUTES);
		}
	}

	private void runSimpleAppiumAndroidTest(URL appiumURL) throws InterruptedException {
		var driver = createAppiumAndroidDriver(appiumURL);

		driver.get("https://www.google.com/");
		driver.getScreenshotAs(OutputType.BASE64);
	}

	private static AndroidDriver createAppiumAndroidDriver(URL appiumURL) {
		var givenCapabilities = new MutableCapabilities();
		givenCapabilities.setCapability("automationName", "UiAutomator2");
		givenCapabilities.setCapability("appium:newCommandTimeout", 120);

		var driver = new AndroidDriver(appiumURL, givenCapabilities);
		return driver;
	}

	/**
	 * Starts the Appium server for a given session.
	 *
	 * @param sessionId The ID of the active session.
	 * @return The Appium server URL.
	 */
	private String startAppiumServer(String sessionId) {
		log.info("Starting Appium server for session {}", sessionId);
		JsonPath response = given()
				.contentType("application/json")
				.body("""
                  { "appiumVersion": "latest" }
                  """)
				.when()
				.post("/sessions/" + sessionId + "/appiumserver")
				.then()
				.statusCode(200)
				.extract().jsonPath();

		String appiumUrl = response.getString("url");
		assertNotNull(appiumUrl, "Appium URL should not be null");
		log.info("Appium server is ready at: {}", appiumUrl);
		return appiumUrl;
	}

	/**
	 * Creates a new API session for the specified operating system.
	 * Asserts that the initial state is PENDING.
	 *
	 * @param os The operating system ("Android" or "ios").
	 * @return The ID of the created session.
	 */
	private String createApiSession(String os) {
		log.info("Creating a new API session for OS: {}", os);
		JsonPath sessionCreationResponse = given()
				.contentType("application/json")
				.body("""
                  {
                  	"device": {
                  		"os": "%s"
					}
				  }
                  """.formatted(os))
				.when()
				.post("/sessions")
				.then()
				.statusCode(200)
				.body("state", equalTo(ApiSessionState.PENDING.name()))
				.extract().jsonPath();
		return sessionCreationResponse.getString("id");
	}

	/**
	 * Waits for a session to transition to an expected state within a given timeout.
	 * This is a generic and reusable method for polling session status.
	 *
	 * @param sessionId     The ID of the session to wait for.
	 * @param expectedState The target ApiSessionState to wait for.
	 * @param timeout       The maximum time to wait.
	 * @param timeUnit      The unit of time for the timeout.
	 */
	private void waitForApiSessionState(String sessionId, ApiSessionState expectedState, long timeout, TimeUnit timeUnit) {
		log.info("Waiting for session {} to become {} (timeout: {} {})", sessionId, expectedState, timeout, timeUnit);
		try {
			Awaitility.await()
					.atMost(timeout, timeUnit)
					.pollInterval(5, TimeUnit.SECONDS)
					.until(() -> getApiSessionState(sessionId) == expectedState);
			log.info("Session {} is now in state: {}", sessionId, expectedState);
		} catch (Exception e) {
			log.error("Session {} did not transition to {} within the specified time.", sessionId, expectedState, e);
			throw e;
		}
	}

	/**
	 * Verifies that the session is in the expected state.
	 *
	 * @param sessionId     The ID of the session to check.
	 * @param expectedState The expected ApiSessionState.
	 */
	private void verifyApiSessionState(String sessionId, ApiSessionState expectedState) {
		ApiSessionState currentState = getApiSessionState(sessionId);
		assertEquals(expectedState, currentState, "Session state is not as expected.");
		log.info("Successfully verified session {} state is {}", sessionId, currentState);
	}

	/**
	 * Closes an active API session.
	 * Asserts that the final state is CLOSING.
	 *
	 * @param sessionId The ID of the session to close.
	 */
	private void closeApiSession(String sessionId) {
		log.info("Sending DELETE request to close session {}", sessionId);
		given()
				.when()
				.delete("/sessions/" + sessionId)
				.then()
				.statusCode(200)
				.body("state", equalTo(ApiSessionState.CLOSING.name()));
		log.info("Session {} successfully marked for closing.", sessionId);
	}

	/**
	 * Retrieves the current state of a session.
	 *
	 * @param sessionId The ID of the session.
	 * @return The current state as a ApiSessionState enum.
	 */
	private ApiSessionState getApiSessionState(String sessionId) {
		String stateStr = given()
				.when()
				.get("/sessions/" + sessionId)
				.then()
				.statusCode(200)
				.extract().jsonPath().getString("state");
		log.debug("Session {} current state string: {}", sessionId, stateStr);
		try {
			return ApiSessionState.valueOf(stateStr);
		} catch (IllegalArgumentException e) {
			log.error("Unknown session state '{}' received for session {}", stateStr, sessionId);
			throw new IllegalStateException("Unknown session state: " + stateStr, e);
		}
	}
}

