package org.example.dictapp

import android.content.Context
import androidx.benchmark.junit4.BenchmarkRule
import androidx.benchmark.junit4.measureRepeated
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileOutputStream

/**
 * Benchmarks to measure JSON parsing overhead in the Kotlin layer.
 *
 * These tests isolate the kotlinx.serialization parsing cost from JNI overhead,
 * helping identify if JSON serialization is a bottleneck.
 *
 * Run with: ./gradlew :app:connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=org.example.dictapp.JsonParsingBenchmark
 */
@RunWith(AndroidJUnit4::class)
class JsonParsingBenchmark {

    @get:Rule
    val benchmarkRule = BenchmarkRule()

    private lateinit var context: Context
    private lateinit var dbPath: String
    private val json = Json { ignoreUnknownKeys = true }

    // Pre-captured JSON strings for parsing benchmarks
    private lateinit var searchResultJson: String
    private lateinit var definitionJson: String
    private var wordId: Long = 0

    @Before
    fun setup() {
        context = ApplicationProvider.getApplicationContext()
        dbPath = File(context.filesDir, "benchmark-dict.db").absolutePath

        // Copy test database from assets
        copyTestDatabase()

        // Initialize
        val result = DictCore.init(dbPath)
        if (result != DictCore.SUCCESS) {
            throw IllegalStateException("Failed to initialize DictCore: $result")
        }

        // Capture JSON strings for parsing benchmarks
        searchResultJson = DictCore.search("hel", 50, 0) ?: "[]"

        val results = DictCore.searchParsed("hello", 1)
        wordId = results.firstOrNull()?.id ?: 1
        definitionJson = DictCore.getDefinition(wordId) ?: "{}"
    }

    @After
    fun teardown() {
        DictCore.close()
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
    // Search Result JSON Parsing
    // ========================================================================

    /**
     * Benchmark: Parse search results JSON (isolated)
     *
     * Measures only kotlinx.serialization parsing time, without JNI overhead.
     */
    @Test
    fun jsonParsing_searchResults() {
        benchmarkRule.measureRepeated {
            val results = json.decodeFromString<List<SearchResult>>(searchResultJson)
            check(results.isNotEmpty())
        }
    }

    /**
     * Benchmark: Parse empty search results
     */
    @Test
    fun jsonParsing_searchResultsEmpty() {
        val emptyJson = "[]"

        benchmarkRule.measureRepeated {
            val results = json.decodeFromString<List<SearchResult>>(emptyJson)
            check(results.isEmpty())
        }
    }

    // ========================================================================
    // Definition JSON Parsing
    // ========================================================================

    /**
     * Benchmark: Parse full definition JSON (isolated)
     *
     * Measures only kotlinx.serialization parsing time for complex nested object.
     */
    @Test
    fun jsonParsing_definition() {
        benchmarkRule.measureRepeated {
            val definition = json.decodeFromString<FullDefinition>(definitionJson)
            check(definition != null)
        }
    }

    // ========================================================================
    // Overhead Comparison
    // ========================================================================

    /**
     * Benchmark: JNI search only (no parsing)
     *
     * Baseline for comparing against parsed version.
     */
    @Test
    fun overhead_searchJniOnly() {
        benchmarkRule.measureRepeated {
            val json = DictCore.search("hel", 50, 0)
            check(json != null)
        }
    }

    /**
     * Benchmark: JNI search + JSON parsing
     *
     * Compare against overhead_searchJniOnly to see parsing cost.
     */
    @Test
    fun overhead_searchWithParsing() {
        benchmarkRule.measureRepeated {
            val results = DictCore.searchParsed("hel", 50)
            check(results.isNotEmpty())
        }
    }

    /**
     * Benchmark: JNI definition only (no parsing)
     *
     * Baseline for comparing against parsed version.
     */
    @Test
    fun overhead_definitionJniOnly() {
        benchmarkRule.measureRepeated {
            val json = DictCore.getDefinition(wordId)
            check(json != null)
        }
    }

    /**
     * Benchmark: JNI definition + JSON parsing
     *
     * Compare against overhead_definitionJniOnly to see parsing cost.
     */
    @Test
    fun overhead_definitionWithParsing() {
        benchmarkRule.measureRepeated {
            val definition = DictCore.getDefinitionParsed(wordId)
            check(definition != null)
        }
    }

    // ========================================================================
    // Synthetic JSON Benchmarks (for scaling analysis)
    // ========================================================================

    /**
     * Benchmark: Parse large search result set
     *
     * Synthetic test with many results to measure scaling.
     */
    @Test
    fun jsonParsing_largeResultSet() {
        // Generate synthetic large result JSON
        val largeJson = buildString {
            append("[")
            repeat(100) { i ->
                if (i > 0) append(",")
                append("""{"id":$i,"word":"word$i","pos":"noun","preview":"Definition $i","score":0.0}""")
            }
            append("]")
        }

        benchmarkRule.measureRepeated {
            val results = json.decodeFromString<List<SearchResult>>(largeJson)
            check(results.size == 100)
        }
    }

    /**
     * Benchmark: Parse complex definition with many entries
     *
     * Synthetic test with complex nested structure.
     * JSON keys use snake_case to match Rust serialization format.
     */
    @Test
    fun jsonParsing_complexDefinition() {
        // Generate synthetic complex definition JSON (snake_case keys match Rust output)
        val complexJson = """
        {
            "word": "test",
            "pos": "noun",
            "language": "English",
            "lang_code": "en",
            "definitions": [
                ${(1..10).joinToString(",") { """{"id":$it,"text":"Definition $it","examples":["Example 1","Example 2"],"tags":["formal","dated"]}""" }}
            ],
            "pronunciations": [
                {"id":1,"ipa":"/test/","audio_url":"https://example.com/test.ogg","accent":"US"},
                {"id":2,"ipa":"/test/","audio_url":null,"accent":"UK"}
            ],
            "etymology": "From Latin testum, meaning earthen pot",
            "translations": [
                ${(1..20).joinToString(",") { """{"id":$it,"target_language":"lang$it","translation":"translation$it"}""" }}
            ]
        }
        """.trimIndent()

        benchmarkRule.measureRepeated {
            val definition = json.decodeFromString<FullDefinition>(complexJson)
            check(definition != null)
            check(definition.definitions.size == 10)
            check(definition.translations.size == 20)
        }
    }
}
