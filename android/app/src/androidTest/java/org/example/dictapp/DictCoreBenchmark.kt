package org.example.dictapp

import android.content.Context
import androidx.benchmark.junit4.BenchmarkRule
import androidx.benchmark.junit4.measureRepeated
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileOutputStream

/**
 * JNI Microbenchmarks for dict-core native library.
 *
 * Performance targets (from ARCHITECTURE.md):
 * - Cold startup (DB exists): < 500ms
 * - Search latency: < 50ms
 * - Definition load: < 20ms
 *
 * Run with: ./gradlew :app:connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=org.example.dictapp.DictCoreBenchmark
 *
 * For more accurate results, run on a release build with:
 *   ./gradlew :app:connectedReleaseAndroidTest (requires signing config)
 *
 * Note: Benchmarks include EMULATOR and DEBUGGABLE suppression for dev testing.
 * For production benchmarks, run on a real device with a release build.
 */
@RunWith(AndroidJUnit4::class)
class DictCoreBenchmark {

    @get:Rule
    val benchmarkRule = BenchmarkRule()

    private lateinit var context: Context
    private lateinit var dbPath: String
    private var wordId: Long = 0

    @Before
    fun setup() {
        context = ApplicationProvider.getApplicationContext()
        dbPath = File(context.filesDir, "benchmark-dict.db").absolutePath

        // Copy test database from assets
        copyTestDatabase()

        // Initialize for tests that need it pre-initialized
        val result = DictCore.init(dbPath)
        if (result != DictCore.SUCCESS) {
            throw IllegalStateException("Failed to initialize DictCore: $result")
        }

        // Get a word ID for definition tests
        val results = DictCore.searchParsed("hello", 1)
        wordId = results.firstOrNull()?.id ?: 1
    }

    @After
    fun teardown() {
        DictCore.close()
        // Clean up test database
        File(dbPath).delete()
    }

    private fun copyTestDatabase() {
        val dbFile = File(dbPath)
        if (dbFile.exists()) {
            dbFile.delete()
        }

        context.assets.open("test-dict.db").use { input ->
            FileOutputStream(dbFile).use { output ->
                input.copyTo(output)
            }
        }
    }

    // ========================================================================
    // Startup Benchmarks
    // ========================================================================

    /**
     * Benchmark: Database initialization (cold start)
     *
     * Target: < 500ms
     *
     * This measures the time to open an existing SQLite database
     * through the JNI layer. This is critical for app startup time.
     */
    @Test
    fun startup_init() {
        // Close current connection for fresh init each iteration
        DictCore.close()

        benchmarkRule.measureRepeated {
            runWithTimingDisabled {
                // Ensure clean state (db file exists but not opened)
                copyTestDatabase()
            }

            val result = DictCore.init(dbPath)
            if (result != DictCore.SUCCESS) {
                throw IllegalStateException("Init failed: $result")
            }

            runWithTimingDisabled {
                DictCore.close()
            }
        }
    }

    // ========================================================================
    // Search Benchmarks (Raw JNI)
    // ========================================================================

    /**
     * Benchmark: Raw JNI search returning JSON string
     *
     * Target: < 50ms
     *
     * Measures native search without Kotlin JSON parsing overhead.
     */
    @Test
    fun search_raw_exactMatch() {
        // Re-init since startup test closed it
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val json = DictCore.search("hello", 50, 0)
            // Prevent dead code elimination
            check(json != null && json.isNotEmpty())
        }
    }

    @Test
    fun search_raw_prefixShort() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val json = DictCore.search("hel", 50, 0)
            check(json != null)
        }
    }

    @Test
    fun search_raw_noMatch() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val json = DictCore.search("xyzzynonexistent", 50, 0)
            // May return empty array JSON
        }
    }

    @Test
    fun search_raw_fuzzyTypo() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            // "helo" should fuzzy match "hello"
            val json = DictCore.search("helo", 50, 0)
            check(json != null)
        }
    }

    // ========================================================================
    // Search Benchmarks (With JSON Parsing)
    // ========================================================================

    /**
     * Benchmark: Search with Kotlin JSON parsing
     *
     * Target: < 50ms (including parsing)
     *
     * Measures complete search flow including JSON deserialization.
     */
    @Test
    fun search_parsed_exactMatch() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val results = DictCore.searchParsed("hello", 50)
            check(results.isNotEmpty())
        }
    }

    @Test
    fun search_parsed_prefixShort() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val results = DictCore.searchParsed("hel", 50)
            check(results.isNotEmpty())
        }
    }

    @Test
    fun search_parsed_limit10() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val results = DictCore.searchParsed("h", 10)
            check(results.size <= 10)
        }
    }

    @Test
    fun search_parsed_limit100() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val results = DictCore.searchParsed("h", 100)
            check(results.size <= 100)
        }
    }

    // ========================================================================
    // Definition Loading Benchmarks
    // ========================================================================

    /**
     * Benchmark: Raw JNI definition load returning JSON string
     *
     * Target: < 20ms
     *
     * Measures native definition retrieval without parsing.
     */
    @Test
    fun definition_raw_single() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val json = DictCore.getDefinition(wordId)
            check(json != null && json.isNotEmpty())
        }
    }

    /**
     * Benchmark: Definition load with Kotlin JSON parsing
     *
     * Target: < 20ms (including parsing)
     *
     * Measures complete definition load including deserialization.
     */
    @Test
    fun definition_parsed_single() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val definition = DictCore.getDefinitionParsed(wordId)
            check(definition != null)
        }
    }

    @Test
    fun definition_raw_notFound() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            // Non-existent ID
            DictCore.getDefinition(999999)
            // Should return null for non-existent
        }
    }

    // ========================================================================
    // End-to-End Flow Benchmarks
    // ========================================================================

    /**
     * Benchmark: Complete user flow (search then load definition)
     *
     * Simulates typical user interaction: type query, see results, tap result.
     */
    @Test
    fun e2e_searchThenDefinition() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            // User types and searches
            val results = DictCore.searchParsed("hello", 10)
            check(results.isNotEmpty())

            // User taps first result
            val definition = DictCore.getDefinitionParsed(results[0].id)
            check(definition != null)
        }
    }

    /**
     * Benchmark: Rapid search simulation (typing)
     *
     * Simulates user typing incrementally: h -> he -> hel -> hell -> hello
     */
    @Test
    fun e2e_rapidTyping() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            DictCore.search("h", 10, 0)
            DictCore.search("he", 10, 0)
            DictCore.search("hel", 10, 0)
            DictCore.search("hell", 10, 0)
            DictCore.search("hello", 10, 0)
        }
    }

    /**
     * Benchmark: Browse multiple results
     *
     * Simulates user browsing through search results, loading each definition.
     */
    @Test
    fun e2e_browseResults() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            val results = DictCore.searchParsed("hel", 5)

            // Load each definition (simulates scrolling/tapping)
            for (result in results) {
                DictCore.getDefinitionParsed(result.id)
            }
        }
    }

    /**
     * Benchmark: Cold start to first result
     *
     * Measures complete flow from app start to displaying first search result.
     * This is the critical path for user-perceived startup time.
     */
    @Test
    fun e2e_coldStartToFirstResult() {
        DictCore.close()

        benchmarkRule.measureRepeated {
            runWithTimingDisabled {
                copyTestDatabase()
            }

            // App starts, initializes database
            val initResult = DictCore.init(dbPath)
            check(initResult == DictCore.SUCCESS)

            // User immediately searches
            val results = DictCore.searchParsed("hello", 10)
            check(results.isNotEmpty())

            runWithTimingDisabled {
                DictCore.close()
            }
        }
    }

    // ========================================================================
    // Stress/Repeated Operation Benchmarks
    // ========================================================================

    /**
     * Benchmark: Many sequential searches
     *
     * Tests for memory leaks or performance degradation over many operations.
     */
    @Test
    fun stress_100SequentialSearches() {
        ensureInitialized()

        val queries = listOf("hello", "world", "help", "test", "word")

        benchmarkRule.measureRepeated {
            repeat(100) { i ->
                DictCore.search(queries[i % queries.size], 20, 0)
            }
        }
    }

    /**
     * Benchmark: Alternating search and definition loads
     *
     * Tests interleaved operations typical of real usage.
     */
    @Test
    fun stress_50SearchDefinitionPairs() {
        ensureInitialized()

        benchmarkRule.measureRepeated {
            repeat(50) {
                val results = DictCore.searchParsed("hel", 5)
                if (results.isNotEmpty()) {
                    DictCore.getDefinitionParsed(results[0].id)
                }
            }
        }
    }

    // ========================================================================
    // Helper Methods
    // ========================================================================

    private fun ensureInitialized() {
        // Re-initialize if needed (some tests close the connection)
        copyTestDatabase()
        DictCore.init(dbPath)
    }
}
