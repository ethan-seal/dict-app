package org.example.dictapp

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
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
 * End-to-end UI tests for the Dictionary App.
 *
 * These tests launch the actual MainActivity with a test database
 * and simulate user interactions through the full app flow.
 *
 * Run with: ./gradlew connectedAndroidTest
 */
@RunWith(AndroidJUnit4::class)
class DictAppE2ETest {

    // Use empty compose rule - we'll launch Activity manually after setup
    @get:Rule
    val composeTestRule = createEmptyComposeRule()

    private lateinit var appContext: Context
    private lateinit var scenario: ActivityScenario<MainActivity>
    private var testDbPath: String? = null

    @Before
    fun setup() {
        // Get contexts
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val testContext = instrumentation.context
        appContext = instrumentation.targetContext

        // Copy test database BEFORE launching the Activity
        val testDbFile = File(appContext.filesDir, "dict.db")
        testContext.assets.open("test-dict.db").use { input ->
            testDbFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        testDbPath = testDbFile.absolutePath

        // Now launch the Activity (ViewModel will find the database)
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }
    
    /**
     * Types text into the search field.
     * Uses OutlinedTextField which works correctly with Compose testing's performTextInput().
     */
    private fun typeInSearchField(text: String) {
        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_INPUT)
            .performTextInput(text)
        
        // Wait for debounce (50ms in ViewModel) and search to complete
        Thread.sleep(150)
        composeTestRule.waitForIdle()
    }

    @After
    fun teardown() {
        scenario.close()
        // Clean up test database
        testDbPath?.let { File(it).delete() }
    }

    // ========================================================================
    // Search Flow Tests
    // ========================================================================

    @Test
    fun searchScreen_initialState_showsEmptyPrompt() {
        // Wait for app to initialize and show search screen
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_EMPTY_PROMPT)
                .fetchSemanticsNodes().isNotEmpty()
        }

        // Should show empty search prompt initially
        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_EMPTY_PROMPT)
            .assertIsDisplayed()
    }

    @Test
    fun searchScreen_typeQuery_showsResults() {
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_EMPTY_PROMPT)
                .fetchSemanticsNodes().isNotEmpty()
        }

        typeInSearchField("hello")

        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }

        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_RESULTS_LIST)
            .assertIsDisplayed()
    }

    @Test
    fun searchScreen_noMatchingResults_showsNoResultsMessage() {
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_EMPTY_PROMPT)
                .fetchSemanticsNodes().isNotEmpty()
        }

        typeInSearchField("xyznonexistent123")

        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.NO_RESULTS_MESSAGE)
                .fetchSemanticsNodes().isNotEmpty()
        }

        composeTestRule
            .onNodeWithTag(TestTags.NO_RESULTS_MESSAGE)
            .assertIsDisplayed()
    }

    // ========================================================================
    // Navigation Flow Tests
    // ========================================================================

    @Test
    fun fullFlow_searchAndViewDefinition() {
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_EMPTY_PROMPT)
                .fetchSemanticsNodes().isNotEmpty()
        }

        typeInSearchField("hello")

        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }

        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_RESULT_CARD + "_4454")
            .performClick()

        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.DEFINITION_HEADER)
                .fetchSemanticsNodes().isNotEmpty()
        }

        composeTestRule
            .onNodeWithTag(TestTags.DEFINITION_HEADER)
            .assertIsDisplayed()
    }

    @Test
    fun fullFlow_searchAndNavigateBack() {
        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_EMPTY_PROMPT)
                .fetchSemanticsNodes().isNotEmpty()
        }

        typeInSearchField("apple")

        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }

        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_RESULT_CARD + "_1740")
            .performClick()

        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.DEFINITION_HEADER)
                .fetchSemanticsNodes().isNotEmpty()
        }

        composeTestRule
            .onNodeWithTag(TestTags.BACK_BUTTON)
            .performClick()

        composeTestRule.waitUntil(timeoutMillis = 15000) {
            composeTestRule
                .onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }

        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_RESULTS_LIST)
            .assertIsDisplayed()
    }
}
