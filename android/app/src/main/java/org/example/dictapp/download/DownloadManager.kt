package org.example.dictapp.download

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit
import org.apache.commons.compress.compressors.zstandard.ZstdCompressorInputStream

/**
 * Manages downloading and decompressing dictionary database files.
 *
 * This class handles:
 * - Downloading zstd-compressed SQLite databases from CDN
 * - Progress tracking during download
 * - Decompression using zstd
 * - Basic integrity verification
 *
 * Usage:
 * ```kotlin
 * val manager = DownloadManager(context)
 * manager.downloadDatabase("english").collect { state ->
 *     when (state) {
 *         is DownloadProgress.Downloading -> updateProgress(state.progress)
 *         is DownloadProgress.Extracting -> showExtractingUI()
 *         is DownloadProgress.Complete -> navigateToSearch(state.dbPath)
 *         is DownloadProgress.Error -> showError(state.message)
 *     }
 * }
 * ```
 */
class DownloadManager(private val context: Context) {

    companion object {
        private const val TAG = "DownloadManager"
        
        // Base URL for dictionary database CDN (DigitalOcean Spaces)
        private const val CDN_BASE_URL = "https://wiktionary.atl1.digitaloceanspaces.com"
        
        // Database filename
        private const val DB_FILENAME = "dict.db"
        
        // Buffer sizes
        private const val DOWNLOAD_BUFFER_SIZE = 8192
        private const val DECOMPRESS_BUFFER_SIZE = 65536
        
        // Timeouts
        private const val CONNECT_TIMEOUT_SECONDS = 30L
        private const val READ_TIMEOUT_SECONDS = 60L
    }

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()

    /**
     * Get the path where the database should be stored.
     */
    fun getDatabasePath(): String {
        val path = File(context.filesDir, DB_FILENAME).absolutePath
        Log.d(TAG, "getDatabasePath() = $path")
        return path
    }

    /**
     * Check if the database already exists.
     */
    fun isDatabaseDownloaded(): Boolean {
        val dbFile = File(getDatabasePath())
        val exists = dbFile.exists()
        val length = if (exists) dbFile.length() else 0L
        Log.d(TAG, "isDatabaseDownloaded: path=${dbFile.absolutePath}, exists=$exists, length=$length")
        return exists && length > 0
    }

    /**
     * Delete the existing database (for re-download).
     */
    fun deleteDatabase(): Boolean {
        val dbFile = File(getDatabasePath())
        return if (dbFile.exists()) dbFile.delete() else true
    }

    /**
     * Download and decompress the dictionary database.
     *
     * @param language Language code (e.g., "english", "spanish")
     * @return Flow of DownloadProgress states
     */
    fun downloadDatabase(language: String): Flow<DownloadProgress> = flow {
        emit(DownloadProgress.Starting)

        try {
            // Construct the download URL
            val url = getDownloadUrl(language)
            val compressedFile = File(context.cacheDir, "${language}-dict.db.zst")
            val finalDbFile = File(getDatabasePath())
            
            Log.d(TAG, "Starting download: url=$url")
            Log.d(TAG, "Compressed file path: ${compressedFile.absolutePath}")
            Log.d(TAG, "Final database path: ${finalDbFile.absolutePath}")

            // Download the compressed file
            downloadFile(url, compressedFile).collect { progress ->
                emit(progress)
            }

            // Verify download
            Log.d(TAG, "Download complete. Compressed file exists=${compressedFile.exists()}, size=${compressedFile.length()}")
            if (!compressedFile.exists() || compressedFile.length() == 0L) {
                emit(DownloadProgress.Error("Download failed: file is empty or missing"))
                return@flow
            }

            // Decompress
            emit(DownloadProgress.Extracting)
            Log.d(TAG, "Starting decompression...")
            try {
                decompressZstd(compressedFile, finalDbFile)
            } catch (e: Exception) {
                Log.e(TAG, "Decompression failed with exception", e)
                throw e
            } catch (e: Error) {
                Log.e(TAG, "Decompression failed with error", e)
                throw e
            }

            // Verify decompression
            val decompressedExists = finalDbFile.exists()
            val decompressedSize = if (decompressedExists) finalDbFile.length() else 0L
            Log.d(TAG, "Decompression complete. File exists=$decompressedExists, size=$decompressedSize")
            
            if (!decompressedExists || decompressedSize == 0L) {
                emit(DownloadProgress.Error("Decompression failed: database file is invalid"))
                return@flow
            }

            // Verify it's a valid SQLite database (check magic bytes)
            val isValidSqlite = verifySqliteDatabase(finalDbFile)
            Log.d(TAG, "SQLite verification: valid=$isValidSqlite")
            if (!isValidSqlite) {
                finalDbFile.delete()
                emit(DownloadProgress.Error("Invalid database file"))
                return@flow
            }

            // Clean up compressed file
            compressedFile.delete()
            
            // Final verification
            Log.d(TAG, "Download complete! Final file: path=${finalDbFile.absolutePath}, exists=${finalDbFile.exists()}, size=${finalDbFile.length()}")

            emit(DownloadProgress.Complete(finalDbFile.absolutePath))

        } catch (e: Exception) {
            Log.e(TAG, "Download failed with exception", e)
            emit(DownloadProgress.Error(e.message ?: "Unknown error occurred"))
        }
    }.flowOn(Dispatchers.IO)

    /**
     * Download a file with progress tracking.
     */
    private fun downloadFile(
        url: String,
        destination: File
    ): Flow<DownloadProgress> = flow {
        val request = Request.Builder()
            .url(url)
            .build()

        httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw DownloadException("HTTP ${response.code}: ${response.message}")
            }

            val body = response.body ?: throw DownloadException("Empty response body")
            val totalBytes = body.contentLength()
            var bytesDownloaded = 0L

            destination.parentFile?.mkdirs()

            body.byteStream().use { input ->
                BufferedOutputStream(FileOutputStream(destination)).use { output ->
                    val buffer = ByteArray(DOWNLOAD_BUFFER_SIZE)
                    var bytesRead: Int

                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        bytesDownloaded += bytesRead

                        val progress = if (totalBytes > 0) {
                            bytesDownloaded.toFloat() / totalBytes.toFloat()
                        } else {
                            0f
                        }

                        emit(
                            DownloadProgress.Downloading(
                                progress = progress,
                                bytesDownloaded = bytesDownloaded,
                                totalBytes = totalBytes
                            )
                        )
                    }
                }
            }
        }
    }

    /**
     * Decompress a zstd-compressed file.
     * Ensures data is synced to disk before returning.
     */
    private suspend fun decompressZstd(source: File, destination: File) = withContext(Dispatchers.IO) {
        Log.d(TAG, "decompressZstd: creating parent dirs")
        destination.parentFile?.mkdirs()

        Log.d(TAG, "decompressZstd: opening streams")
        var bytesWritten = 0L
        try {
            ZstdCompressorInputStream(BufferedInputStream(FileInputStream(source))).use { zstdInput ->
                Log.d(TAG, "decompressZstd: ZstdCompressorInputStream opened successfully")
                FileOutputStream(destination).use { fos ->
                    val output = BufferedOutputStream(fos)
                    val buffer = ByteArray(DECOMPRESS_BUFFER_SIZE)
                    var bytesRead: Int

                    while (zstdInput.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        bytesWritten += bytesRead
                        // Log progress every 50MB
                        if (bytesWritten % (50 * 1024 * 1024) < DECOMPRESS_BUFFER_SIZE) {
                            Log.d(TAG, "decompressZstd: written ${bytesWritten / (1024 * 1024)} MB")
                        }
                    }
                    
                    Log.d(TAG, "decompressZstd: flushing buffer, total=${bytesWritten / (1024 * 1024)} MB")
                    output.flush()
                    Log.d(TAG, "decompressZstd: syncing to disk")
                    fos.fd.sync()
                    Log.d(TAG, "decompressZstd: synced to disk successfully")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "decompressZstd: failed after writing $bytesWritten bytes", e)
            // Clean up partial file
            if (destination.exists()) {
                destination.delete()
            }
            throw e
        }
    }

    /**
     * Verify that a file is a valid SQLite database.
     * SQLite databases start with the magic string "SQLite format 3\0"
     */
    private fun verifySqliteDatabase(file: File): Boolean {
        if (!file.exists() || file.length() < 16) return false

        return try {
            FileInputStream(file).use { input ->
                val header = ByteArray(16)
                input.read(header)
                val magic = String(header, 0, 15, Charsets.US_ASCII)
                magic == "SQLite format 3"
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Get the download URL for a specific language.
     */
    private fun getDownloadUrl(language: String): String {
        return "$CDN_BASE_URL/$language-dict.db.zst"
    }

    /**
     * Get available languages and their metadata.
     */
    fun getAvailableLanguages(): List<LanguageInfo> {
        // In a real implementation, this could be fetched from an API
        return listOf(
            LanguageInfo(
                code = "english",
                displayName = "English",
                estimatedSizeMb = 300,
                wordCount = "500,000+"
            )
            // Future: Add more languages
            // LanguageInfo("spanish", "Spanish", 250, "400,000+"),
            // LanguageInfo("french", "French", 280, "450,000+"),
        )
    }
}

/**
 * States for download progress tracking.
 */
sealed class DownloadProgress {
    /** Download is starting */
    data object Starting : DownloadProgress()

    /** Actively downloading */
    data class Downloading(
        val progress: Float,
        val bytesDownloaded: Long,
        val totalBytes: Long
    ) : DownloadProgress()

    /** Extracting/decompressing the downloaded file */
    data object Extracting : DownloadProgress()

    /** Download and extraction completed successfully */
    data class Complete(val dbPath: String) : DownloadProgress()

    /** An error occurred */
    data class Error(val message: String) : DownloadProgress()
}

/**
 * Information about an available language.
 */
data class LanguageInfo(
    val code: String,
    val displayName: String,
    val estimatedSizeMb: Int,
    val wordCount: String
)

/**
 * Exception for download-related errors.
 */
class DownloadException(message: String, cause: Throwable? = null) : Exception(message, cause)
