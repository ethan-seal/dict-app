package org.example.dictapp

import com.google.gson.Gson
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
     * @return JSON string containing array of SearchResult, or null on error
     */
    external fun search(query: String, limit: Int): String?

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
     * @return List of SearchResult objects
     */
    fun searchParsed(query: String, limit: Int = 50): List<SearchResult> {
        val json = search(query, limit) ?: return emptyList()
        return try {
            val type = object : TypeToken<List<SearchResult>>() {}.type
            gson.fromJson(json, type)
        } catch (e: Exception) {
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
        val json = getDefinition(wordId) ?: return null
        return try {
            gson.fromJson(json, FullDefinition::class.java)
        } catch (e: Exception) {
            null
        }
    }
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
    val lang_code: String = "",
    val definitions: List<Definition>,
    val pronunciations: List<Pronunciation>,
    val etymology: String?,
    val translations: List<Translation>
) {
    /** Language code uppercased (e.g. "EN") */
    val langCode: String get() = lang_code.uppercase()
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
    val audioUrl: String?,
    val accent: String?
)

/**
 * Translation to another language.
 */
data class Translation(
    val id: Long,
    val targetLanguage: String,
    val translation: String
)
