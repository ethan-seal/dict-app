package org.example.dictapp

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.common.truth.Truth.assertThat
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Diagnostic tests for debugging device-specific issues.
 *
 * These tests are designed to run on any device/emulator and provide detailed
 * diagnostic output to help identify issues with the search->definition flow.
 *
 * Run with: ./gradlew connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=org.example.dictapp.DeviceDiagnosticTest
 *
 * View logs with: adb logcat -s DeviceDiagnostic:D DictCore:D
 */
@RunWith(AndroidJUnit4::class)
class DeviceDiagnosticTest {

    private lateinit var appContext: Context
    private var realDbPath: String? = null
    private var testDbPath: String? = null
    private var useRealDb: Boolean = false

    companion object {
        private const val TAG = "DeviceDiagnostic"
    }

    @Before
    fun setup() {
        val testContext = InstrumentationRegistry.getInstrumentation().context
        appContext = InstrumentationRegistry.getInstrumentation().targetContext

        // Log device info
        Log.i(TAG, "=== Device Info ===")
        Log.i(TAG, "Model: ${Build.MODEL}")
        Log.i(TAG, "Manufacturer: ${Build.MANUFACTURER}")
        Log.i(TAG, "SDK: ${Build.VERSION.SDK_INT}")
        Log.i(TAG, "ABI: ${Build.SUPPORTED_ABIS.joinToString()}")
        Log.i(TAG, "==================")

        // Check for real database first
        val realDb = File(appContext.filesDir, "dict.db")
        if (realDb.exists() && realDb.length() > 0) {
            realDbPath = realDb.absolutePath
            useRealDb = true
            Log.i(TAG, "Found real database: $realDbPath (${realDb.length()} bytes)")
        } else {
            Log.i(TAG, "Real database not found at ${realDb.absolutePath}")
        }

        // Also copy test database for comparison
        val testDbFile = File(appContext.cacheDir, "test-dict.db")
        try {
            testContext.assets.open("test-dict.db").use { input ->
                testDbFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            testDbPath = testDbFile.absolutePath
            Log.i(TAG, "Test database copied to: $testDbPath")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to copy test database: ${e.message}")
        }
    }

    @After
    fun teardown() {
        DictCore.close()
        testDbPath?.let { File(it).delete() }
    }

    @Test
    fun diagnose_searchToDefinitionFlow() {
        // Prefer real database, fall back to test database
        val dbPath = if (useRealDb) {
            Log.i(TAG, "=== Testing with REAL database ===")
            realDbPath!!
        } else if (testDbPath != null) {
            Log.i(TAG, "=== Testing with TEST database ===")
            testDbPath!!
        } else {
            Log.e(TAG, "No database available!")
            throw IllegalStateException("No database available for testing")
        }

        // Initialize
        Log.i(TAG, "Initializing with: $dbPath")
        val initResult = DictCore.init(dbPath)
        Log.i(TAG, "Init result: $initResult (SUCCESS=${DictCore.SUCCESS})")
        assertThat(initResult).isEqualTo(DictCore.SUCCESS)

        // Test search
        val testQueries = listOf("hello", "world", "test", "computer", "apple")
        
        for (query in testQueries) {
            Log.i(TAG, "--- Testing query: '$query' ---")
            
            val results = DictCore.searchParsed(query, 10)
            Log.i(TAG, "Search returned ${results.size} results")
            
            if (results.isEmpty()) {
                Log.w(TAG, "No results for '$query' - skipping")
                continue
            }

            // Log all results with their IDs
            results.forEachIndexed { index, result ->
                Log.i(TAG, "  [$index] id=${result.id}, word='${result.word}', pos='${result.pos}'")
            }

            // Try to get definition for EACH result
            var successCount = 0
            var failCount = 0
            
            results.forEach { result ->
                Log.i(TAG, "Getting definition for id=${result.id}...")
                val definition = DictCore.getDefinitionParsed(result.id)
                
                if (definition != null) {
                    successCount++
                    Log.i(TAG, "  SUCCESS: word='${definition.word}', definitions=${definition.definitions.size}")
                } else {
                    failCount++
                    Log.e(TAG, "  FAILED: Definition is null for id=${result.id}, word='${result.word}'")
                }
            }
            
            Log.i(TAG, "Query '$query': $successCount succeeded, $failCount failed")
            
            // If using real database, warn but don't fail
            if (useRealDb && failCount > 0) {
                Log.e(TAG, "ISSUE DETECTED: Failed to get definitions for $failCount search results on real database!")
            }
        }

        Log.i(TAG, "=== Diagnostic test complete ===")
    }

    @Test
    fun diagnose_idRangeAndTypes() {
        val dbPath = if (useRealDb) realDbPath!! else testDbPath ?: throw IllegalStateException("No DB")
        
        Log.i(TAG, "=== Testing ID ranges and types ===")
        
        val initResult = DictCore.init(dbPath)
        assertThat(initResult).isEqualTo(DictCore.SUCCESS)

        // Search for something that should have results
        val results = DictCore.searchParsed("a", 100)
        Log.i(TAG, "Got ${results.size} results for 'a'")

        if (results.isEmpty()) {
            Log.w(TAG, "No results - cannot test ID ranges")
            return
        }

        // Analyze IDs
        val ids = results.map { it.id }
        val minId = ids.minOrNull() ?: 0L
        val maxId = ids.maxOrNull() ?: 0L
        
        Log.i(TAG, "ID range: $minId to $maxId")
        Log.i(TAG, "Sample IDs: ${ids.take(10)}")

        // Check for suspicious ID values
        val negativeIds = ids.filter { it < 0 }
        if (negativeIds.isNotEmpty()) {
            Log.e(TAG, "Found negative IDs: $negativeIds")
        }

        val veryLargeIds = ids.filter { it > Int.MAX_VALUE.toLong() }
        if (veryLargeIds.isNotEmpty()) {
            Log.w(TAG, "Found IDs > Int.MAX_VALUE: $veryLargeIds")
        }

        // Test a few specific IDs
        Log.i(TAG, "Testing specific ID lookups...")
        listOf(minId, maxId, ids[ids.size / 2]).forEach { testId ->
            Log.i(TAG, "Testing ID $testId...")
            val def = DictCore.getDefinitionParsed(testId)
            if (def != null) {
                Log.i(TAG, "  Found: ${def.word}")
            } else {
                Log.e(TAG, "  NOT FOUND!")
            }
        }

        Log.i(TAG, "=== ID range test complete ===")
    }

    @Test
    fun diagnose_firstResultDefinition() {
        val dbPath = if (useRealDb) realDbPath!! else testDbPath ?: throw IllegalStateException("No DB")
        
        Log.i(TAG, "=== Testing first result definition ===")
        
        val initResult = DictCore.init(dbPath)
        assertThat(initResult).isEqualTo(DictCore.SUCCESS)

        // This is the exact flow the app uses
        val query = "hello"
        Log.i(TAG, "Searching for: $query")
        
        val results = DictCore.searchParsed(query, 15)
        Log.i(TAG, "Got ${results.size} results")
        
        if (results.isEmpty()) {
            Log.w(TAG, "No results!")
            return
        }

        // Get first result
        val first = results[0]
        Log.i(TAG, "First result: id=${first.id}, word='${first.word}', pos='${first.pos}'")
        
        // Get raw JSON for comparison
        val rawJson = DictCore.getDefinition(first.id)
        Log.i(TAG, "Raw JSON response: ${rawJson?.take(500) ?: "null"}")
        
        // Get parsed definition
        val definition = DictCore.getDefinitionParsed(first.id)
        if (definition != null) {
            Log.i(TAG, "Definition found!")
            Log.i(TAG, "  word: ${definition.word}")
            Log.i(TAG, "  pos: ${definition.pos}")
            Log.i(TAG, "  language: ${definition.language}")
            Log.i(TAG, "  definitions: ${definition.definitions.size}")
            Log.i(TAG, "  pronunciations: ${definition.pronunciations.size}")
        } else {
            Log.e(TAG, "Definition is NULL!")
            
            // This is the bug! Try to understand why
            Log.e(TAG, "Attempting debug...")
            Log.e(TAG, "  Search returned word='${first.word}' with id=${first.id}")
            Log.e(TAG, "  But getDefinition(${first.id}) returned null")
            Log.e(TAG, "  This suggests the ID is invalid or corrupted")
            
            // Fail the test with a clear message
            assertThat(definition != null).isTrue()
        }
    }

    @Test
    fun diagnose_compareTestAndRealDb() {
        if (!useRealDb || testDbPath == null) {
            Log.i(TAG, "Skipping comparison - need both databases")
            return
        }

        Log.i(TAG, "=== Comparing TEST vs REAL database ===")

        // Test with test database first
        Log.i(TAG, "--- TEST DATABASE ---")
        var initResult = DictCore.init(testDbPath!!)
        assertThat(initResult).isEqualTo(DictCore.SUCCESS)
        
        var results = DictCore.searchParsed("hello", 5)
        Log.i(TAG, "Test DB: ${results.size} results for 'hello'")
        results.forEach { r ->
            val def = DictCore.getDefinitionParsed(r.id)
            Log.i(TAG, "  id=${r.id} -> ${if (def != null) "OK" else "NULL"}")
        }
        
        DictCore.close()

        // Test with real database
        Log.i(TAG, "--- REAL DATABASE ---")
        initResult = DictCore.init(realDbPath!!)
        assertThat(initResult).isEqualTo(DictCore.SUCCESS)
        
        results = DictCore.searchParsed("hello", 5)
        Log.i(TAG, "Real DB: ${results.size} results for 'hello'")
        results.forEach { r ->
            val def = DictCore.getDefinitionParsed(r.id)
            Log.i(TAG, "  id=${r.id} -> ${if (def != null) "OK" else "NULL"}")
        }

        Log.i(TAG, "=== Comparison complete ===")
    }
}
