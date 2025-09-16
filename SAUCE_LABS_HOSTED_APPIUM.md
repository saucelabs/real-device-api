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

@Slf4j
public class OpenApiAppiumTest {

  private static String sessionId; // The ID for our reserved device session
  private static URL appiumUrl;     // The Appium URL, reused for all tests

  /**
   * Runs once before any @Test methods. This method reserves a device via the
   * Sauce Labs OpenAPI and starts a persistent Appium server for that device.
   * The resulting session ID and Appium URL are stored for all subsequent tests.
   */
  @BeforeAll
  public static void setupSuite() {
    // ... API authentication setup ...

    log.info("Requesting a device and starting the Appium server...");
    sessionId = createApiSession("Android");
    waitForApiSessionState(sessionId, ApiSessionState.ACTIVE, 3, TimeUnit.MINUTES);
    appiumUrl = startAppiumServer(sessionId);
    log.info("✅ Device and Appium are ready for the entire suite!");
  }

  /**
   * The FINAL cleanup. This releases the device after all tests are done.
   */
  @AfterAll
  public static void tearDownSuite() {
    if (sessionId != null) {
      log.info("Closing the device session...");
      closeApiSession(sessionId);
    }
  }

  // --- Rapid-Fire Tests ---
  // Each of these methods runs back-to-back on the SAME device.

  @Test
  public void test_userLogin() {
    log.info("Executing test: User Login");
    AndroidDriver driver = createAppiumAndroidDriver(appiumUrl);
    try {
      // ... test logic for logging in ...
      assertTrue(driver.findElement(By.id("user_avatar")).isDisplayed());
    } finally {
      // This quits the Appium client connection for this specific test.
      // The underlying device session remains active for the next test.
      driver.quit();
    }
  }

  @Test
  public void test_addToCart() {
    log.info("Executing test: Add to Cart");
    AndroidDriver driver = createAppiumAndroidDriver(appiumUrl);
    try {
      // Assumes user is already logged in from the previous test
      // ... test logic for adding an item to the cart ...
      assertEquals("1", driver.findElement(By.id("cart_badge")).getText());
    } finally {
      // This quits the Appium client connection for this specific test.
      // The underlying device session remains active for the next test.
      driver.quit();
    }
  }

  // ... Helper methods for createApiSession(), etc. ...
}
```

***Note:*** The code above is a conceptual illustration of the test structure. For a complete, runnable project—including all helper methods 
for authenticating and interacting with the Sauce Labs RDC Access API—please see our [full Java sample](./samples/java).