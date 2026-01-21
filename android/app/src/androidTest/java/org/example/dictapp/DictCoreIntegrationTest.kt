package org.example.dictapp

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.common.truth.Truth.assertThat
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Integration tests for DictCore JNI bindings.
 *
 * These tests verify the Rust-Android boundary works correctly by:
 * - Testing database initialization and lifecycle
 * - Testing search functionality with known test data
 * - Testing entry retrieval
 * - Testing error handling
 *
 * Run with: ./gradlew connectedAndroidTest
 */
@RunWith(AndroidJUnit4::class)
class DictCoreIntegrationTest {

    private lateinit var appContext: Context
    private var testDbPath: String? = null

    @Before
    fun setup() {
        // targetContext = app under test, context = test APK (where our assets are)
        val testContext = InstrumentationRegistry.getInstrumentation().context
        appContext = InstrumentationRegistry.getInstrumentation().targetContext

        // Copy test database from test assets to app's cache directory
        val testDbFile = File(appContext.cacheDir, "test-dict.db")
        testContext.assets.open("test-dict.db").use { input ->
            testDbFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        testDbPath = testDbFile.absolutePath
    }

    @After
    fun teardown() {
        // Always close to avoid state leaking between tests
        DictCore.close()

        // Clean up test database (if setup succeeded)
        testDbPath?.let { File(it).delete() }
    }

    // ========================================================================
    // Initialization Tests
    // ========================================================================

    @Test
    fun init_withValidPath_returnsSuccess() {
        val result = DictCore.init(testDbPath!!)
        assertThat(result).isEqualTo(DictCore.SUCCESS)
    }

    @Test
    fun init_withInvalidPath_returnsError() {
        val result = DictCore.init("/nonexistent/path/to/db.db")
        assertThat(result).isNotEqualTo(DictCore.SUCCESS)
    }

    @Test
    fun init_calledTwice_succeedsOrHandlesGracefully() {
        val result1 = DictCore.init(testDbPath!!)
        assertThat(result1).isEqualTo(DictCore.SUCCESS)

        // Second init should either succeed (reinitialize) or fail gracefully
        val result2 = DictCore.init(testDbPath!!)
        // We don't crash - that's the main assertion
        assertThat(result2).isAnyOf(DictCore.SUCCESS, DictCore.ERROR_INIT_FAILED)
    }

    // ========================================================================
    // Search Tests
    // ========================================================================

    @Test
    fun search_exactMatch_returnsResults() {
        DictCore.init(testDbPath!!)

        val results = DictCore.searchParsed("hello", 50)

        assertThat(results).isNotEmpty()
        assertThat(results.map { it.word }).contains("hello")
    }

    @Test
    fun search_prefixMatch_returnsResults() {
        DictCore.init(testDbPath!!)

        // "app" should match "apple"
        val results = DictCore.searchParsed("app", 50)

        assertThat(results).isNotEmpty()
        assertThat(results.any { it.word.startsWith("app") }).isTrue()
    }

    @Test
    fun search_noMatch_returnsEmptyList() {
        DictCore.init(testDbPath!!)

        val results = DictCore.searchParsed("xyznonexistent", 50)

        assertThat(results).isEmpty()
    }

    @Test
    fun search_emptyQuery_returnsEmptyOrHandlesGracefully() {
        DictCore.init(testDbPath!!)

        val results = DictCore.searchParsed("", 50)

        // Should return empty or some results, but not crash
        assertThat(results).isNotNull()
    }

    @Test
    fun search_withLimit_respectsLimit() {
        DictCore.init(testDbPath!!)

        val results = DictCore.searchParsed("a", 2)

        assertThat(results.size).isAtMost(2)
    }

    @Test
    fun search_returnsCorrectFields() {
        DictCore.init(testDbPath!!)

        val results = DictCore.searchParsed("hello", 50)

        assertThat(results).isNotEmpty()
        val result = results.first { it.word == "hello" }
        assertThat(result.id).isGreaterThan(0L)
        assertThat(result.word).isEqualTo("hello")
        assertThat(result.pos).isNotEmpty()
        // preview may be empty depending on implementation
    }

    @Test
    fun search_multiplePartsOfSpeech_returnsAll() {
        DictCore.init(testDbPath!!)

        // "hello" exists as intj, noun, verb in test data
        val results = DictCore.searchParsed("hello", 50)

        val partsOfSpeech = results.filter { it.word == "hello" }.map { it.pos }.toSet()
        // Should have multiple POS entries
        assertThat(partsOfSpeech.size).isGreaterThan(1)
    }

    @Test
    fun search_withoutInit_returnsEmptyList() {
        // Don't init - search should handle gracefully
        val results = DictCore.searchParsed("hello", 50)

        assertThat(results).isEmpty()
    }

    // ========================================================================
    // Get Definition Tests
    // ========================================================================

    @Test
    fun getDefinition_validId_returnsFullDefinition() {
        DictCore.init(testDbPath!!)

        // First search to get a valid ID
        val searchResults = DictCore.searchParsed("hello", 50)
        assertThat(searchResults).isNotEmpty()

        val definition = DictCore.getDefinitionParsed(searchResults[0].id)

        assertThat(definition).isNotNull()
        assertThat(definition!!.word).isEqualTo("hello")
        assertThat(definition.definitions).isNotEmpty()
    }

    @Test
    fun getDefinition_invalidId_returnsNull() {
        DictCore.init(testDbPath!!)

        val definition = DictCore.getDefinitionParsed(-1)

        assertThat(definition).isNull()
    }

    @Test
    fun getDefinition_nonexistentId_returnsNull() {
        DictCore.init(testDbPath!!)

        val definition = DictCore.getDefinitionParsed(999999999)

        assertThat(definition).isNull()
    }

    @Test
    fun getDefinition_includesPronunciations() {
        DictCore.init(testDbPath!!)

        // "hello" has pronunciations in test data
        val searchResults = DictCore.searchParsed("hello", 50)
        val helloResult = searchResults.first { it.word == "hello" }

        val definition = DictCore.getDefinitionParsed(helloResult.id)

        assertThat(definition).isNotNull()
        assertThat(definition!!.pronunciations).isNotEmpty()
    }

    @Test
    fun getDefinition_includesEtymology() {
        DictCore.init(testDbPath!!)

        // "hello" has etymology in test data
        val searchResults = DictCore.searchParsed("hello", 50)
        val helloResult = searchResults.first { it.word == "hello" && it.pos == "intj" }

        val definition = DictCore.getDefinitionParsed(helloResult.id)

        assertThat(definition).isNotNull()
        assertThat(definition!!.etymology).isNotNull()
        assertThat(definition.etymology).isNotEmpty()
    }

    @Test
    fun getDefinition_withoutInit_returnsNull() {
        // Don't init
        val definition = DictCore.getDefinitionParsed(1)

        assertThat(definition).isNull()
    }

    // ========================================================================
    // Close Tests
    // ========================================================================

    @Test
    fun close_afterInit_allowsReinit() {
        DictCore.init(testDbPath!!)
        DictCore.close()

        val result = DictCore.init(testDbPath!!)
        assertThat(result).isEqualTo(DictCore.SUCCESS)

        // Verify it works after reinit
        val results = DictCore.searchParsed("hello", 50)
        assertThat(results).isNotEmpty()
    }

    @Test
    fun close_calledMultipleTimes_doesNotCrash() {
        DictCore.init(testDbPath!!)
        DictCore.close()
        DictCore.close()
        DictCore.close()
        // No crash = success
    }

    @Test
    fun close_withoutInit_doesNotCrash() {
        DictCore.close()
        // No crash = success
    }

    // ========================================================================
    // Data Integrity Tests
    // ========================================================================

    @Test
    fun searchThenGetDefinition_dataIsConsistent() {
        DictCore.init(testDbPath!!)

        val searchResults = DictCore.searchParsed("computer", 50)
        assertThat(searchResults).isNotEmpty()

        val searchResult = searchResults.first { it.word == "computer" }
        val definition = DictCore.getDefinitionParsed(searchResult.id)

        assertThat(definition).isNotNull()
        assertThat(definition!!.word).isEqualTo(searchResult.word)
        assertThat(definition.pos).isEqualTo(searchResult.pos)
    }

    @Test
    fun definitionFields_haveCorrectTypes() {
        DictCore.init(testDbPath!!)

        val searchResults = DictCore.searchParsed("apple", 50)
        val appleResult = searchResults.first { it.word == "apple" && it.pos == "noun" }

        val definition = DictCore.getDefinitionParsed(appleResult.id)

        assertThat(definition).isNotNull()
        assertThat(definition!!.word).isInstanceOf(String::class.java)
        assertThat(definition.pos).isInstanceOf(String::class.java)
        assertThat(definition.language).isInstanceOf(String::class.java)
        assertThat(definition.definitions).isInstanceOf(List::class.java)
        assertThat(definition.pronunciations).isInstanceOf(List::class.java)
        assertThat(definition.translations).isInstanceOf(List::class.java)
    }
}
