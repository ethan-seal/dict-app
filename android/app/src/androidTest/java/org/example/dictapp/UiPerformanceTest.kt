package org.example.dictapp

import android.content.Context
import android.util.Log
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.common.truth.Truth.assertThat
import org.example.dictapp.ui.TestTags
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * UI-level performance tests measuring actual user-perceived latency.
 *
 * Unlike DictCoreBenchmark and PerformanceTest which measure raw JNI/data layer timing,
 * these tests measure the full pipeline from user input to rendered UI:
 *   keystroke → debounce → coroutine dispatch → JNI → parsing → StateFlow →
 *   Compose recomposition → LazyColumn layout → frame rendered
 *
 * Performance targets:
 * - Search to results visible: < 100ms (50ms debounce + 50ms processing/render)
 * - Result tap to definition visible: < 100ms
 * - Rapid typing, last keystroke to results: < 100ms
 * - Cold start to search ready: < 500ms
 *
 * Run with:
 *   ./gradlew :app:connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=org.example.dictapp.UiPerformanceTest
 */
@RunWith(AndroidJUnit4::class)
class UiPerformanceTest {

    companion object {
        private const val TAG = "UiPerformanceTest"

        /** Matches nodes whose test tag starts with the given prefix. */
        private fun hasTestTagPrefix(prefix: String) =
            SemanticsMatcher("has test tag starting with '$prefix'") { node ->
                SemanticsProperties.TestTag in node.config &&
                    node.config[SemanticsProperties.TestTag].startsWith(prefix)
            }
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

        // Copy test database BEFORE launching the Activity
        val testDbFile = File(appContext.filesDir, "dict.db")
        testContext.assets.open("test-dict.db").use { input ->
            testDbFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        testDbPath = testDbFile.absolutePath

        scenario = ActivityScenario.launch(MainActivity::class.java)

        // Wait for app to be ready before measuring
        composeTestRule.waitUntil(timeoutMillis = 10_000) {
            composeTestRule.onAllNodesWithTag(TestTags.SEARCH_INPUT)
                .fetchSemanticsNodes().isNotEmpty()
        }
        composeTestRule.waitForIdle()
    }

    @After
    fun teardown() {
        scenario.close()
        testDbPath?.let { File(it).delete() }
    }

    /**
     * Measures time from typing a query to search results being visible on screen.
     *
     * Pipeline: keystroke → 50ms debounce → IO dispatch → JNI search → JSON parse →
     *           StateFlow emit → collectAsState → recomposition → LazyColumn layout
     *
     * Target: < 100ms
     */
    @Test
    fun ui_searchToResultsVisible() {
        val startNanos = System.nanoTime()

        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_INPUT)
            .performTextInput("hello")

        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }

        val elapsedMs = (System.nanoTime() - startNanos) / 1_000_000.0
        Log.i(TAG, "ui_searchToResultsVisible: ${elapsedMs}ms (target: <100ms)")

        assertThat(elapsedMs).isLessThan(100.0)
    }

    /**
     * Measures time from tapping a search result to the definition screen being visible.
     *
     * Pipeline: click → navigation → ViewModel loads definition → recomposition → layout
     *
     * Target: < 100ms
     */
    @Test
    fun ui_resultTapToDefinitionVisible() {
        // Setup: get search results visible first
        composeTestRule
            .onNodeWithTag(TestTags.SEARCH_INPUT)
            .performTextInput("hello")

        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }
        composeTestRule.waitForIdle()

        // Find the first result card (tags are "search_result_card_${id}")
        val cardMatcher = hasTestTagPrefix(TestTags.SEARCH_RESULT_CARD + "_")
        val resultNodes = composeTestRule
            .onAllNodes(cardMatcher)
            .fetchSemanticsNodes()
        assertThat(resultNodes).isNotEmpty()

        // Measure: tap result → definition visible
        val startNanos = System.nanoTime()

        composeTestRule.onAllNodes(cardMatcher)[0].performClick()

        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithTag(TestTags.DEFINITION_SCREEN)
                .fetchSemanticsNodes().isNotEmpty()
        }

        val elapsedMs = (System.nanoTime() - startNanos) / 1_000_000.0
        Log.i(TAG, "ui_resultTapToDefinitionVisible: ${elapsedMs}ms (target: <100ms)")

        assertThat(elapsedMs).isLessThan(100.0)
    }

    /**
     * Measures time from the last keystroke in a rapid typing sequence to results visible.
     *
     * Simulates: user types "h", "e", "l", "l", "o" with each keystroke resetting
     * the debounce. Measures from the final "o" keystroke to results appearing.
     *
     * Target: < 100ms (from last keystroke)
     */
    @Test
    fun ui_rapidTyping_finalResultVisible() {
        val searchInput = composeTestRule.onNodeWithTag(TestTags.SEARCH_INPUT)

        // Type all but the last character
        searchInput.performTextInput("hell")

        // Brief pause to let the system process intermediate state,
        // but not long enough for debounce to fire and show results
        Thread.sleep(30)

        // Measure from last keystroke to results visible
        val startNanos = System.nanoTime()

        searchInput.performTextInput("o")

        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithTag(TestTags.SEARCH_RESULTS_LIST)
                .fetchSemanticsNodes().isNotEmpty()
        }

        val elapsedMs = (System.nanoTime() - startNanos) / 1_000_000.0
        Log.i(TAG, "ui_rapidTyping_finalResultVisible: ${elapsedMs}ms (target: <100ms)")

        assertThat(elapsedMs).isLessThan(100.0)
    }

    /**
     * Measures time from Activity launch to the search field being interactable.
     *
     * Pipeline: Activity.onCreate → setContent → ViewModel init → DB check →
     *           Compose initial composition → SearchScreen layout → frame rendered
     *
     * Target: < 500ms
     */
    @Test
    fun ui_coldStartToSearchReady() {
        // Close the scenario from setup — we need a fresh launch with timing
        scenario.close()
        testDbPath?.let { File(it).delete() }

        // Re-copy the database
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val testContext = instrumentation.context
        val testDbFile = File(appContext.filesDir, "dict.db")
        testContext.assets.open("test-dict.db").use { input ->
            testDbFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        testDbPath = testDbFile.absolutePath

        // Measure: launch → search input visible
        val startNanos = System.nanoTime()

        scenario = ActivityScenario.launch(MainActivity::class.java)

        composeTestRule.waitUntil(timeoutMillis = 10_000) {
            composeTestRule.onAllNodesWithTag(TestTags.SEARCH_INPUT)
                .fetchSemanticsNodes().isNotEmpty()
        }

        val elapsedMs = (System.nanoTime() - startNanos) / 1_000_000.0
        Log.i(TAG, "ui_coldStartToSearchReady: ${elapsedMs}ms (target: <500ms)")

        assertThat(elapsedMs).isLessThan(500.0)
    }
}
