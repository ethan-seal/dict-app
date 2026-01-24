package org.example.dictapp.viewmodel

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
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
import org.example.dictapp.download.DownloadManager
import org.example.dictapp.download.DownloadProgress
import org.example.dictapp.download.LanguageInfo

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
class DictViewModel(application: Application) : AndroidViewModel(application) {

    // Download manager for handling database downloads
    private val downloadManager = DownloadManager(application)

    // Current download job (for cancellation)
    private var downloadJob: Job? = null

    // Database initialization state
    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    // Whether database exists (for determining start destination)
    private val _isDatabaseReady = MutableStateFlow(false)
    val isDatabaseReady: StateFlow<Boolean> = _isDatabaseReady.asStateFlow()

    // Available languages for download
    private val _availableLanguages = MutableStateFlow<List<LanguageInfo>>(emptyList())
    val availableLanguages: StateFlow<List<LanguageInfo>> = _availableLanguages.asStateFlow()

    // Selected language for download
    private val _selectedLanguage = MutableStateFlow<LanguageInfo?>(null)
    val selectedLanguage: StateFlow<LanguageInfo?> = _selectedLanguage.asStateFlow()

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
        // Check if database exists and load available languages
        checkDatabaseStatus()
        loadAvailableLanguages()

        // Set up debounced search
        viewModelScope.launch {
            _query
                .debounce(50) // Wait 50ms after last keystroke
                .distinctUntilChanged()
                .filter { it.isNotBlank() }
                .collect { query ->
                    performSearch(query)
                }
        }
    }

    /**
     * Check if the database is already downloaded.
     */
    private fun checkDatabaseStatus() {
        Log.d(TAG, "checkDatabaseStatus: checking...")
        
        // List all files in filesDir for debugging
        val filesDir = getApplication<Application>().filesDir
        Log.d(TAG, "checkDatabaseStatus: filesDir=${filesDir.absolutePath}")
        val files = filesDir.listFiles()
        if (files.isNullOrEmpty()) {
            Log.d(TAG, "checkDatabaseStatus: filesDir is empty")
        } else {
            files.forEach { file ->
                Log.d(TAG, "checkDatabaseStatus: found file=${file.name}, size=${file.length()}")
            }
        }
        
        val isDownloaded = downloadManager.isDatabaseDownloaded()
        Log.d(TAG, "checkDatabaseStatus: isDownloaded=$isDownloaded")
        _isDatabaseReady.value = isDownloaded
        if (isDownloaded) {
            // Auto-initialize if database exists
            val dbPath = downloadManager.getDatabasePath()
            Log.d(TAG, "checkDatabaseStatus: initializing with path=$dbPath")
            val success = initialize(dbPath)
            Log.d(TAG, "checkDatabaseStatus: initialization success=$success")
        }
    }
    
    companion object {
        private const val TAG = "DictViewModel"
    }

    /**
     * Load the list of available languages.
     */
    private fun loadAvailableLanguages() {
        _availableLanguages.value = downloadManager.getAvailableLanguages()
        // Default to first language (English)
        _selectedLanguage.value = _availableLanguages.value.firstOrNull()
    }

    /**
     * Select a language for download.
     */
    fun selectLanguage(language: LanguageInfo) {
        _selectedLanguage.value = language
    }

    /**
     * Get the path to the database file.
     */
    fun getDatabasePath(): String = downloadManager.getDatabasePath()

    /**
     * Initialize the dictionary core with the database path.
     *
     * @param dbPath Absolute path to the SQLite database file
     * @return true if initialization succeeded
     */
    fun initialize(dbPath: String): Boolean {
        Log.d(TAG, "initialize: calling DictCore.init with path=$dbPath")
        val result = DictCore.init(dbPath)
        Log.d(TAG, "initialize: DictCore.init returned $result (SUCCESS=${DictCore.SUCCESS})")
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
            try {
                val results = DictCore.searchParsed(query, 50)
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
        // Cancel any existing download
        downloadJob?.cancel()

        downloadJob = viewModelScope.launch {
            _downloadState.value = DownloadState.Downloading(
                progress = 0f,
                bytesDownloaded = 0,
                totalBytes = 0
            )

            try {
                downloadManager.downloadDatabase(language).collect { progress ->
                    when (progress) {
                        is DownloadProgress.Starting -> {
                            _downloadState.value = DownloadState.Downloading(
                                progress = 0f,
                                bytesDownloaded = 0,
                                totalBytes = 0
                            )
                        }

                        is DownloadProgress.Downloading -> {
                            _downloadState.value = DownloadState.Downloading(
                                progress = progress.progress,
                                bytesDownloaded = progress.bytesDownloaded,
                                totalBytes = progress.totalBytes
                            )
                        }

                        is DownloadProgress.Extracting -> {
                            _downloadState.value = DownloadState.Extracting
                        }

                        is DownloadProgress.Complete -> {
                            // Initialize the core with the downloaded database
                            val success = initialize(progress.dbPath)
                            if (success) {
                                _isDatabaseReady.value = true
                                _downloadState.value = DownloadState.Complete
                            } else {
                                _downloadState.value = DownloadState.Error(
                                    "Failed to initialize dictionary database"
                                )
                            }
                        }

                        is DownloadProgress.Error -> {
                            _downloadState.value = DownloadState.Error(progress.message)
                        }
                    }
                }
            } catch (e: Exception) {
                _downloadState.value = DownloadState.Error(
                    e.message ?: "Download failed"
                )
            }
        }
    }

    /**
     * Cancel an ongoing download.
     */
    fun cancelDownload() {
        downloadJob?.cancel()
        downloadJob = null
        _downloadState.value = DownloadState.Idle
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
