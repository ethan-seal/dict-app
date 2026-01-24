package org.example.dictapp

import android.content.Context
import androidx.benchmark.junit4.BenchmarkRule
import androidx.benchmark.junit4.measureRepeated
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
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
 * These tests isolate the Gson parsing cost from JNI overhead,
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
    private val gson = Gson()

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
     * Measures only Gson parsing time, without JNI overhead.
     */
    @Test
    fun jsonParsing_searchResults() {
        val type = object : TypeToken<List<SearchResult>>() {}.type

        benchmarkRule.measureRepeated {
            val results: List<SearchResult> = gson.fromJson(searchResultJson, type)
            check(results.isNotEmpty())
        }
    }

    /**
     * Benchmark: Parse empty search results
     */
    @Test
    fun jsonParsing_searchResultsEmpty() {
        val emptyJson = "[]"
        val type = object : TypeToken<List<SearchResult>>() {}.type

        benchmarkRule.measureRepeated {
            val results: List<SearchResult> = gson.fromJson(emptyJson, type)
            check(results.isEmpty())
        }
    }

    // ========================================================================
    // Definition JSON Parsing
    // ========================================================================

    /**
     * Benchmark: Parse full definition JSON (isolated)
     *
     * Measures only Gson parsing time for complex nested object.
     */
    @Test
    fun jsonParsing_definition() {
        benchmarkRule.measureRepeated {
            val definition = gson.fromJson(definitionJson, FullDefinition::class.java)
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
        val type = object : TypeToken<List<SearchResult>>() {}.type

        benchmarkRule.measureRepeated {
            val results: List<SearchResult> = gson.fromJson(largeJson, type)
            check(results.size == 100)
        }
    }

    /**
     * Benchmark: Parse complex definition with many entries
     *
     * Synthetic test with complex nested structure.
     */
    @Test
    fun jsonParsing_complexDefinition() {
        // Generate synthetic complex definition JSON
        val complexJson = """
        {
            "word": "test",
            "pos": "noun",
            "language": "English",
            "definitions": [
                ${(1..10).joinToString(",") { """{"id":$it,"text":"Definition $it","examples":["Example 1","Example 2"],"tags":["formal","dated"]}""" }}
            ],
            "pronunciations": [
                {"id":1,"ipa":"/test/","audioUrl":"https://example.com/test.ogg","accent":"US"},
                {"id":2,"ipa":"/test/","audioUrl":null,"accent":"UK"}
            ],
            "etymology": "From Latin testum, meaning earthen pot",
            "translations": [
                ${(1..20).joinToString(",") { """{"id":$it,"targetLanguage":"lang$it","translation":"translation$it"}""" }}
            ]
        }
        """.trimIndent()

        benchmarkRule.measureRepeated {
            val definition = gson.fromJson(complexJson, FullDefinition::class.java)
            check(definition != null)
            check(definition.definitions.size == 10)
            check(definition.translations.size == 20)
        }
    }
}
