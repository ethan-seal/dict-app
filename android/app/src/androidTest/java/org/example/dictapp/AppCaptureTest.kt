package org.example.dictapp

import android.content.Context
import android.util.Log
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.example.dictapp.ui.TestTags
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * UI capture test for generating screenshots and video of the app in action.
 * 
 * This test walks through key app flows with deliberate pauses, designed
 * to be run alongside screen recording for UI/UX review.
 * 
 * Run with: ./capture-app-media.sh
 * 
 * Emits log markers (CAPTURE_MARKER:*) that the capture script uses to
 * trigger screenshots at key moments.
 */
@RunWith(AndroidJUnit4::class)
class AppCaptureTest {

    companion object {
        private const val TAG = "AppCapture"
        
        // Pause durations (ms) - longer pauses for video readability
        private const val SCENE_PAUSE = 1500L      // Pause to show a scene
        private const val TYPING_DELAY = 100L      // Delay between keystrokes
        private const val TRANSITION_PAUSE = 800L  // Pause after navigation
        
        // Log marker prefix - capture script watches for these
        const val MARKER_PREFIX = "CAPTURE_MARKER"
    }

    @get:Rule
    val composeTestRule = createEmptyComposeRule()

    private lateinit var appContext: Context
    private lateinit var scenario: ActivityScenario<MainActivity>
    private var testDbPath: String? = null

    @Before
    fun setup() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val testContext = instrumentation.context
        appContext = instrumentation.targetContext

        // Copy test database
        val testDbFile = File(appContext.filesDir, "dict.db")
        testContext.assets.open("test-dict.db").use { input ->
            testDbFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        testDbPath = testDbFile.absolutePath

        scenario = ActivityScenario.launch(MainActivity::class.java)
    }

    @After
    fun teardown() {
        scenario.close()
        testDbPath?.let { File(it).delete() }
    }

    /**
     * Emits a marker that the capture script uses to trigger a screenshot.
     */
    private fun captureMarker(name: String) {
        Log.i(TAG, "$MARKER_PREFIX:$name")
        // Brief pause to ensure screenshot is captured cleanly
        Thread.sleep(200)
    }

    /**
     * Types text slowly for video capture (character by character).
     */
    private fun typeSlowly(text: String) {
        text.forEach { char ->
            composeTestRule
                .onNodeWithTag(TestTags.SEARCH_INPUT)
                .performTextInput(char.toString())
            Thread.sleep(TYPING_DELAY)
        }
        // Wait for search debounce + results
        Thread.sleep(500)
        composeTestRule.waitForIdle()
    }

    /**
     * Main capture flow - walks through the app demonstrating key features.
     */
    @Test
    fun captureAppFlow() {
        // === Scene 1: Initial empty state ===
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_EMPTY_PROMPT)
                .fetchSemanticsNodes().isNotEmpty()
        }
        
        captureMarker("01_initial_state")
        Thread.sleep(SCENE_PAUSE)

        // === Scene 2: Search for "hello" ===
        typeSlowly("hello")
        
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }
        
        captureMarker("02_search_results")
        Thread.sleep(SCENE_PAUSE)

        // === Scene 3: View definition for "hello" ===
        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_RESULT_CARD + "_4454")
            .performClick()
        
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.DEFINITION_HEADER)
                .fetchSemanticsNodes().isNotEmpty()
        }
        Thread.sleep(TRANSITION_PAUSE)
        
        captureMarker("03_definition_hello")
        Thread.sleep(SCENE_PAUSE)

        // === Scene 4: Navigate back ===
        composeTestRule
            .onNodeWithTag(TestTags.BACK_BUTTON)
            .performClick()
        
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }
        Thread.sleep(TRANSITION_PAUSE)
        
        captureMarker("04_back_to_results")
        Thread.sleep(SCENE_PAUSE)

        // === Scene 5: Clear and search for something else ===
        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_INPUT)
            .performTextClearance()
        
        Thread.sleep(300)
        typeSlowly("apple")
        
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }
        
        captureMarker("05_search_apple")
        Thread.sleep(SCENE_PAUSE)

        // === Scene 6: View apple definition ===
        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_RESULT_CARD + "_1740")
            .performClick()
        
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.DEFINITION_HEADER)
                .fetchSemanticsNodes().isNotEmpty()
        }
        Thread.sleep(TRANSITION_PAUSE)
        
        captureMarker("06_definition_apple")
        Thread.sleep(SCENE_PAUSE)

        // === Scene 7: Show no results case ===
        composeTestRule
            .onNodeWithTag(TestTags.BACK_BUTTON)
            .performClick()
        
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }
        
        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_INPUT)
            .performTextClearance()
        
        Thread.sleep(300)
        typeSlowly("xyznotfound")
        
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.NO_RESULTS_MESSAGE)
                .fetchSemanticsNodes().isNotEmpty()
        }
        
        captureMarker("07_no_results")
        Thread.sleep(SCENE_PAUSE)

        // Final marker
        captureMarker("DONE")
    }
}
