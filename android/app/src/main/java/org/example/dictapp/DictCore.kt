package org.example.dictapp

import android.util.Log
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.google.gson.reflect.TypeToken

/**
 * JNI bindings to the Rust dict-core library.
 *
 * This object provides the Kotlin interface to the native dictionary operations.
 * The native library handles SQLite database operations, full-text search, and
 * all dictionary data processing.
 *
 * Usage:
 * ```kotlin
 * // Initialize with database path
 * val result = DictCore.init(context.filesDir.absolutePath + "/dict.db")
 * if (result == DictCore.SUCCESS) {
 *     // Search for words
 *     val results = DictCore.searchParsed("hello", 50)
 *     // Get full definition
 *     val definition = DictCore.getDefinitionParsed(results[0].id)
 * }
 * // Clean up when done
 * DictCore.close()
 * ```
 */
object DictCore {
    // Error codes matching FfiError in Rust
    const val SUCCESS = 0
    const val ERROR_NULL_POINTER = 1
    const val ERROR_INVALID_UTF8 = 2
    const val ERROR_INIT_FAILED = 3
    const val ERROR_NOT_INITIALIZED = 4
    const val ERROR_SEARCH_FAILED = 5
    const val ERROR_JSON_FAILED = 6

    private val gson = Gson()

    private val SEARCH_RESULT_LIST_TYPE = object : TypeToken<List<SearchResult>>() {}.type

    init {
        System.loadLibrary("dict_core")
    }

    /**
     * Initialize the dictionary database.
     *
     * @param dbPath Absolute path to the SQLite database file
     * @return Error code (SUCCESS = 0 on success)
     */
    external fun init(dbPath: String): Int

    /**
     * Search for words matching the query.
     *
     * @param query Search query string
     * @param limit Maximum number of results to return
     * @param offset Number of results to skip (for pagination)
     * @return JSON string containing array of SearchResult, or null on error
     */
    external fun search(query: String, limit: Int, offset: Int): String?

    /**
     * Get the full definition for a word.
     *
     * @param wordId The unique ID of the word
     * @return JSON string containing FullDefinition, or null if not found/error
     */
    external fun getDefinition(wordId: Long): String?

    /**
     * Close the dictionary and free resources.
     */
    external fun close()

    /**
     * Search with parsed results.
     *
     * @param query Search query string
     * @param limit Maximum number of results
     * @param offset Number of results to skip (for pagination)
     * @return List of SearchResult objects
     */
    fun searchParsed(query: String, limit: Int = 50, offset: Int = 0): List<SearchResult> {
        val json = search(query, limit, offset)
        if (json == null) {
            Log.w(TAG, "searchParsed('$query'): native returned null")
            return emptyList()
        }
        return try {
            val results: List<SearchResult> = gson.fromJson(json, SEARCH_RESULT_LIST_TYPE)
            Log.d(TAG, "searchParsed('$query'): got ${results.size} results")
            results
        } catch (e: Exception) {
            Log.e(TAG, "searchParsed('$query'): Gson parse failed", e)
            emptyList()
        }
    }

    /**
     * Get definition with parsed result.
     *
     * @param wordId The unique ID of the word
     * @return FullDefinition object, or null if not found
     */
    fun getDefinitionParsed(wordId: Long): FullDefinition? {
        val json = getDefinition(wordId)
        if (json == null) {
            Log.w(TAG, "getDefinitionParsed($wordId): native returned null")
            return null
        }
        Log.d(TAG, "getDefinitionParsed($wordId): got JSON length=${json.length}")
        return try {
            val result = gson.fromJson(json, FullDefinition::class.java)
            if (result == null) {
                Log.w(TAG, "getDefinitionParsed($wordId): Gson returned null (JSON was 'null'?)")
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "getDefinitionParsed($wordId): Gson parse failed", e)
            Log.e(TAG, "getDefinitionParsed($wordId): JSON preview: ${json.take(500)}")
            null
        }
    }
    
    private const val TAG = "DictCore"
}

/**
 * Search result entry for display in results list.
 */
data class SearchResult(
    val id: Long,
    val word: String,
    val pos: String,
    val preview: String,
    val score: Double = 0.0
)

/**
 * Complete definition with all word information.
 */
data class FullDefinition(
    val word: String,
    val pos: String,
    val language: String,
    val lang_code: String? = null,
    val definitions: List<Definition>,
    val pronunciations: List<Pronunciation>,
    val etymology: String?,
    val translations: List<Translation>
) {
    /** Language code uppercased (e.g. "EN") */
    val langCode: String get() = lang_code?.uppercase().orEmpty()
}

/**
 * A single definition/meaning.
 */
data class Definition(
    val id: Long,
    val text: String,
    val examples: List<String>,
    val tags: List<String>
)

/**
 * Pronunciation information.
 */
data class Pronunciation(
    val id: Long,
    val ipa: String?,
    @SerializedName("audio_url") val audioUrl: String?,
    val accent: String?
)

/**
 * Translation to another language.
 */
data class Translation(
    val id: Long,
    @SerializedName("target_language") val targetLanguage: String,
    val translation: String
)
