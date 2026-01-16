package org.example.dictapp.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.example.dictapp.DictCore
import org.example.dictapp.FullDefinition
import org.example.dictapp.SearchResult

/**
 * State for search operations.
 */
sealed class SearchState {
    /** No search performed yet */
    data object Idle : SearchState()

    /** Search in progress */
    data object Loading : SearchState()

    /** Search completed successfully */
    data class Success(val results: List<SearchResult>) : SearchState()

    /** Search failed */
    data class Error(val message: String) : SearchState()
}

/**
 * State for definition loading.
 */
sealed class DefinitionState {
    /** No definition loaded */
    data object Idle : DefinitionState()

    /** Loading definition */
    data object Loading : DefinitionState()

    /** Definition loaded successfully */
    data class Success(val definition: FullDefinition) : DefinitionState()

    /** Failed to load definition */
    data class Error(val message: String) : DefinitionState()
}

/**
 * State for database download.
 */
sealed class DownloadState {
    /** Ready to start download */
    data object Idle : DownloadState()

    /** Download in progress */
    data class Downloading(
        val progress: Float,
        val bytesDownloaded: Long,
        val totalBytes: Long
    ) : DownloadState()

    /** Extracting/decompressing downloaded file */
    data object Extracting : DownloadState()

    /** Download completed successfully */
    data object Complete : DownloadState()

    /** Download failed */
    data class Error(val message: String) : DownloadState()
}

/**
 * ViewModel for the Dictionary app.
 *
 * Manages:
 * - Search state and query debouncing
 * - Definition loading
 * - Database download progress
 * - Core library initialization
 */
@OptIn(FlowPreview::class)
class DictViewModel : ViewModel() {

    // Database initialization state
    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    // Search state
    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _isSearchActive = MutableStateFlow(false)
    val isSearchActive: StateFlow<Boolean> = _isSearchActive.asStateFlow()

    private val _searchState = MutableStateFlow<SearchState>(SearchState.Idle)
    val searchState: StateFlow<SearchState> = _searchState.asStateFlow()

    // Definition state
    private val _definitionState = MutableStateFlow<DefinitionState>(DefinitionState.Idle)
    val definitionState: StateFlow<DefinitionState> = _definitionState.asStateFlow()

    // Download state
    private val _downloadState = MutableStateFlow<DownloadState>(DownloadState.Idle)
    val downloadState: StateFlow<DownloadState> = _downloadState.asStateFlow()

    init {
        // Set up debounced search
        viewModelScope.launch {
            _query
                .debounce(300) // Wait 300ms after last keystroke
                .distinctUntilChanged()
                .filter { it.isNotBlank() }
                .collect { query ->
                    performSearch(query)
                }
        }
    }

    /**
     * Initialize the dictionary core with the database path.
     *
     * @param dbPath Absolute path to the SQLite database file
     * @return true if initialization succeeded
     */
    fun initialize(dbPath: String): Boolean {
        val result = DictCore.init(dbPath)
        _isInitialized.value = (result == DictCore.SUCCESS)
        return _isInitialized.value
    }

    /**
     * Update the search query.
     * This triggers a debounced search automatically.
     */
    fun onQueryChange(newQuery: String) {
        _query.value = newQuery

        if (newQuery.isBlank()) {
            _searchState.value = SearchState.Idle
        }
    }

    /**
     * Update search bar active state.
     */
    fun onSearchActiveChange(active: Boolean) {
        _isSearchActive.value = active
    }

    /**
     * Perform search on background thread.
     */
    private fun performSearch(query: String) {
        viewModelScope.launch {
            _searchState.value = SearchState.Loading

            try {
                val results = withContext(Dispatchers.IO) {
                    DictCore.searchParsed(query, 50)
                }
                _searchState.value = SearchState.Success(results)
            } catch (e: Exception) {
                _searchState.value = SearchState.Error(
                    e.message ?: "Search failed"
                )
            }
        }
    }

    /**
     * Load the full definition for a word.
     *
     * @param wordId The unique ID of the word
     */
    fun loadDefinition(wordId: Long) {
        viewModelScope.launch {
            _definitionState.value = DefinitionState.Loading

            try {
                val definition = withContext(Dispatchers.IO) {
                    DictCore.getDefinitionParsed(wordId)
                }

                if (definition != null) {
                    _definitionState.value = DefinitionState.Success(definition)
                } else {
                    _definitionState.value = DefinitionState.Error("Definition not found")
                }
            } catch (e: Exception) {
                _definitionState.value = DefinitionState.Error(
                    e.message ?: "Failed to load definition"
                )
            }
        }
    }

    /**
     * Clear the current definition state.
     */
    fun clearDefinition() {
        _definitionState.value = DefinitionState.Idle
    }

    /**
     * Start downloading the dictionary database.
     *
     * @param language Language code to download (e.g., "english")
     */
    fun startDownload(language: String) {
        viewModelScope.launch {
            _downloadState.value = DownloadState.Downloading(
                progress = 0f,
                bytesDownloaded = 0,
                totalBytes = 0
            )

            // TODO: Implement actual download logic
            // This is a placeholder for the download implementation
            // The actual implementation would:
            // 1. Determine CDN URL for the language
            // 2. Download the .db.zst file with progress tracking
            // 3. Decompress with zstd
            // 4. Verify checksum
            // 5. Initialize DictCore with the path

            // For now, simulate progress (remove this in real implementation)
            try {
                // Simulated download progress
                for (i in 0..100 step 10) {
                    kotlinx.coroutines.delay(100)
                    _downloadState.value = DownloadState.Downloading(
                        progress = i / 100f,
                        bytesDownloaded = (i * 3_000_000L),
                        totalBytes = 300_000_000L
                    )
                }

                _downloadState.value = DownloadState.Extracting
                kotlinx.coroutines.delay(500)

                _downloadState.value = DownloadState.Complete
            } catch (e: Exception) {
                _downloadState.value = DownloadState.Error(
                    e.message ?: "Download failed"
                )
            }
        }
    }

    /**
     * Reset download state to allow retry.
     */
    fun resetDownload() {
        _downloadState.value = DownloadState.Idle
    }

    /**
     * Clean up resources when ViewModel is destroyed.
     */
    override fun onCleared() {
        super.onCleared()
        DictCore.close()
    }
}
