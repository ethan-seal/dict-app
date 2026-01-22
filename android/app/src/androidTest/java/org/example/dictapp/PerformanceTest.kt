package org.example.dictapp

import android.content.Context
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.common.truth.Truth.assertThat
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileOutputStream
import kotlin.system.measureNanoTime
import kotlin.system.measureTimeMillis

/**
 * Performance tests for dict-core JNI operations.
 *
 * These tests measure actual timings and assert they meet performance targets.
 * Unlike the BenchmarkRule-based tests, these work on all API levels without
 * special permissions.
 *
 * Performance targets (from ARCHITECTURE.md):
 * - Cold startup (DB exists): < 500ms
 * - Search latency: < 50ms
 * - Definition load: < 20ms
 *
 * Run with:
 *   ./gradlew :app:connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=org.example.dictapp.PerformanceTest
 */
@RunWith(AndroidJUnit4::class)
class PerformanceTest {

    companion object {
        private const val TAG = "PerformanceTest"
        private const val WARMUP_ITERATIONS = 5
        private const val MEASURE_ITERATIONS = 20
    }

    private lateinit var testContext: Context  // Test APK context (has assets)
    private lateinit var appContext: Context   // App context (for file storage)
    private lateinit var dbPath: String
    private var wordId: Long = 0

    @Before
    fun setup() {
        // testContext = test APK (where our assets are)
        // appContext = app under test (for file storage)
        testContext = InstrumentationRegistry.getInstrumentation().context
        appContext = InstrumentationRegistry.getInstrumentation().targetContext
        dbPath = File(appContext.filesDir, "perf-test-dict.db").absolutePath
        copyTestDatabase()

        val result = DictCore.init(dbPath)
        assertThat(result).isEqualTo(DictCore.SUCCESS)

        // Get a word ID for definition tests
        val results = DictCore.searchParsed("hello", 1)
        wordId = results.firstOrNull()?.id ?: 1
    }

    @After
    fun teardown() {
        DictCore.close()
        File(dbPath).delete()
    }

    private fun copyTestDatabase() {
        val dbFile = File(dbPath)
        if (dbFile.exists()) dbFile.delete()

        testContext.assets.open("test-dict.db").use { input ->
            FileOutputStream(dbFile).use { output ->
                input.copyTo(output)
            }
        }
    }

    /**
     * Measure operation timing with warmup and multiple iterations.
     * Returns median time in milliseconds.
     */
    private fun measureOperation(name: String, operation: () -> Unit): Double {
        // Warmup
        repeat(WARMUP_ITERATIONS) { operation() }

        // Measure
        val times = mutableListOf<Long>()
        repeat(MEASURE_ITERATIONS) {
            val nanos = measureNanoTime { operation() }
            times.add(nanos)
        }

        times.sort()
        val medianNanos = times[times.size / 2]
        val medianMs = medianNanos / 1_000_000.0
        val minMs = times.first() / 1_000_000.0
        val maxMs = times.last() / 1_000_000.0

        Log.i(TAG, "$name: median=${medianMs}ms, min=${minMs}ms, max=${maxMs}ms")
        return medianMs
    }

    // ========================================================================
    // Startup Tests
    // ========================================================================

    @Test
    fun startup_init_underTarget() {
        DictCore.close()

        val medianMs = measureOperation("startup_init") {
            copyTestDatabase()
            val result = DictCore.init(dbPath)
            assertThat(result).isEqualTo(DictCore.SUCCESS)
            DictCore.close()
        }

        // Re-init for other tests
        copyTestDatabase()
        DictCore.init(dbPath)

        assertThat(medianMs).isLessThan(500.0) // Target: < 500ms
        Log.i(TAG, "PASS: startup_init ${medianMs}ms < 500ms target")
    }

    // ========================================================================
    // Search Tests
    // ========================================================================

    @Test
    fun search_exactMatch_underTarget() {
        val medianMs = measureOperation("search_exactMatch") {
            val json = DictCore.search("hello", 50)
            assertThat(json).isNotNull()
        }

        assertThat(medianMs).isLessThan(50.0) // Target: < 50ms
        Log.i(TAG, "PASS: search_exactMatch ${medianMs}ms < 50ms target")
    }

    @Test
    fun search_prefix_underTarget() {
        val medianMs = measureOperation("search_prefix") {
            val json = DictCore.search("hel", 50)
            assertThat(json).isNotNull()
        }

        assertThat(medianMs).isLessThan(50.0) // Target: < 50ms
        Log.i(TAG, "PASS: search_prefix ${medianMs}ms < 50ms target")
    }

    @Test
    fun search_fuzzyTypo_underTarget() {
        val medianMs = measureOperation("search_fuzzyTypo") {
            val json = DictCore.search("helo", 50) // typo for "hello"
            assertThat(json).isNotNull()
        }

        assertThat(medianMs).isLessThan(50.0) // Target: < 50ms
        Log.i(TAG, "PASS: search_fuzzyTypo ${medianMs}ms < 50ms target")
    }

    @Test
    fun search_withParsing_underTarget() {
        val medianMs = measureOperation("search_withParsing") {
            val results = DictCore.searchParsed("hello", 50)
            assertThat(results).isNotEmpty()
        }

        assertThat(medianMs).isLessThan(50.0) // Target: < 50ms
        Log.i(TAG, "PASS: search_withParsing ${medianMs}ms < 50ms target")
    }

    // ========================================================================
    // Definition Loading Tests
    // ========================================================================

    @Test
    fun definition_raw_underTarget() {
        val medianMs = measureOperation("definition_raw") {
            val json = DictCore.getDefinition(wordId)
            assertThat(json).isNotNull()
        }

        assertThat(medianMs).isLessThan(20.0) // Target: < 20ms
        Log.i(TAG, "PASS: definition_raw ${medianMs}ms < 20ms target")
    }

    @Test
    fun definition_withParsing_underTarget() {
        val medianMs = measureOperation("definition_withParsing") {
            val definition = DictCore.getDefinitionParsed(wordId)
            assertThat(definition).isNotNull()
        }

        assertThat(medianMs).isLessThan(20.0) // Target: < 20ms
        Log.i(TAG, "PASS: definition_withParsing ${medianMs}ms < 20ms target")
    }

    // ========================================================================
    // End-to-End Flow Tests
    // ========================================================================

    @Test
    fun e2e_searchThenDefinition_underTarget() {
        val medianMs = measureOperation("e2e_searchThenDefinition") {
            val results = DictCore.searchParsed("hello", 10)
            assertThat(results).isNotEmpty()
            val definition = DictCore.getDefinitionParsed(results[0].id)
            assertThat(definition).isNotNull()
        }

        // Combined target: search (50ms) + definition (20ms) = 70ms
        assertThat(medianMs).isLessThan(70.0)
        Log.i(TAG, "PASS: e2e_searchThenDefinition ${medianMs}ms < 70ms target")
    }

    @Test
    fun e2e_rapidTyping() {
        val queries = listOf("h", "he", "hel", "hell", "hello")

        val medianMs = measureOperation("e2e_rapidTyping") {
            for (query in queries) {
                DictCore.search(query, 10)
            }
        }

        // 5 searches at 50ms each = 250ms max
        assertThat(medianMs).isLessThan(250.0)
        Log.i(TAG, "PASS: e2e_rapidTyping (5 searches) ${medianMs}ms < 250ms target")
    }

    @Test
    fun e2e_coldStartToFirstResult() {
        DictCore.close()

        val medianMs = measureOperation("e2e_coldStartToFirstResult") {
            copyTestDatabase()
            DictCore.init(dbPath)
            val results = DictCore.searchParsed("hello", 10)
            assertThat(results).isNotEmpty()
            DictCore.close()
        }

        // Re-init for cleanup
        copyTestDatabase()
        DictCore.init(dbPath)

        // Combined target: startup (500ms) + search (50ms) = 550ms
        assertThat(medianMs).isLessThan(550.0)
        Log.i(TAG, "PASS: e2e_coldStartToFirstResult ${medianMs}ms < 550ms target")
    }

    // ========================================================================
    // Stress Tests
    // ========================================================================

    @Test
    fun stress_100SequentialSearches() {
        val queries = listOf("hello", "world", "help", "test", "word")

        val totalMs = measureTimeMillis {
            repeat(100) { i ->
                DictCore.search(queries[i % queries.size], 20)
            }
        }

        val perSearchMs = totalMs / 100.0
        Log.i(TAG, "stress_100SequentialSearches: total=${totalMs}ms, per-search=${perSearchMs}ms")

        // Each search should still be under target
        assertThat(perSearchMs).isLessThan(50.0)
        Log.i(TAG, "PASS: stress_100SequentialSearches avg ${perSearchMs}ms < 50ms target")
    }

    @Test
    fun stress_50SearchDefinitionPairs() {
        val totalMs = measureTimeMillis {
            repeat(50) {
                val results = DictCore.searchParsed("hel", 5)
                if (results.isNotEmpty()) {
                    DictCore.getDefinitionParsed(results[0].id)
                }
            }
        }

        val perPairMs = totalMs / 50.0
        Log.i(TAG, "stress_50SearchDefinitionPairs: total=${totalMs}ms, per-pair=${perPairMs}ms")

        // Each pair (search + definition) should be under combined target
        assertThat(perPairMs).isLessThan(70.0)
        Log.i(TAG, "PASS: stress_50SearchDefinitionPairs avg ${perPairMs}ms < 70ms target")
    }
}
