package org.example.dictapp.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.example.dictapp.DictCore
import org.example.dictapp.FullDefinition
import java.io.File

/**
 * State for the quick definition lookup.
 */
sealed class QuickDefinitionState {
    /** Loading the definition */
    data object Loading : QuickDefinitionState()

    /** Definition found and loaded */
    data class Success(val definition: FullDefinition) : QuickDefinitionState()

    /** Word not found in dictionary */
    data class NotFound(val word: String) : QuickDefinitionState()

    /** Database not available (not downloaded yet) */
    data object DatabaseNotAvailable : QuickDefinitionState()

    /** Generic error */
    data class Error(val message: String) : QuickDefinitionState()
}

/**
 * Quick definition dialog shown when text is selected in any app.
 *
 * This dialog provides a compact view of the word definition with:
 * - Word and part of speech
 * - Pronunciation (IPA)
 * - First 2-3 definitions with examples
 * - "See more" button to open the full app
 * - Proper handling of missing database
 *
 * @param word The selected word to look up
 * @param onDismiss Callback when the dialog should be dismissed
 * @param onOpenFullApp Callback to open the full app with the word
 */
@Composable
fun QuickDefinitionDialog(
    word: String,
    onDismiss: () -> Unit,
    onOpenFullApp: (String) -> Unit = {}
) {
    val context = LocalContext.current
    var state by remember { mutableStateOf<QuickDefinitionState>(QuickDefinitionState.Loading) }

    // Look up the word
    LaunchedEffect(word) {
        state = QuickDefinitionState.Loading

        state = withContext(Dispatchers.IO) {
            lookupWord(context, word)
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = MaterialTheme.shapes.large,
            tonalElevation = 6.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp)
            ) {
                // Title - the word being looked up
                Text(
                    text = word,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )

                Spacer(modifier = Modifier.height(16.dp))

                // Content based on state
                when (val currentState = state) {
                    is QuickDefinitionState.Loading -> {
                        LoadingContent()
                    }

                    is QuickDefinitionState.Success -> {
                        DefinitionContent(
                            definition = currentState.definition,
                            onSeeMore = { onOpenFullApp(word) }
                        )
                    }

                    is QuickDefinitionState.NotFound -> {
                        NotFoundContent(word = currentState.word)
                    }

                    is QuickDefinitionState.DatabaseNotAvailable -> {
                        DatabaseNotAvailableContent(
                            onOpenApp = { onOpenFullApp(word) }
                        )
                    }

                    is QuickDefinitionState.Error -> {
                        ErrorContent(message = currentState.message)
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Action buttons
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("Close")
                    }
                }
            }
        }
    }
}

/**
 * Loading state content.
 */
@Composable
private fun LoadingContent() {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        CircularProgressIndicator()
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Looking up definition...",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Definition content when word is found.
 */
@Composable
private fun DefinitionContent(
    definition: FullDefinition,
    onSeeMore: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
    ) {
        // Part of speech
        Text(
            text = definition.pos,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            fontStyle = FontStyle.Italic
        )

        // Pronunciation (if available)
        definition.pronunciations.firstOrNull()?.ipa?.let { ipa ->
            Text(
                text = "/$ipa/",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Definitions (show first 3)
        definition.definitions.take(3).forEachIndexed { index, def ->
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        text = "${index + 1}. ${def.text}",
                        style = MaterialTheme.typography.bodyMedium
                    )

                    // Show first example if available
                    def.examples.firstOrNull()?.let { example ->
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "\"$example\"",
                            style = MaterialTheme.typography.bodySmall,
                            fontStyle = FontStyle.Italic,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        // Show "See more" if there are more definitions
        if (definition.definitions.size > 3) {
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "+${definition.definitions.size - 3} more definitions",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                TextButton(onClick = onSeeMore) {
                    Text("See more")
                }
            }
        } else {
            // Still show "See more" button even if all definitions are shown
            // to allow viewing etymology, translations, etc.
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onSeeMore) {
                    Text("See full entry")
                }
            }
        }
    }
}

/**
 * Content when word is not found.
 */
@Composable
private fun NotFoundContent(word: String) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "Word not found",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.error
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "\"$word\" was not found in the dictionary.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Content when database is not available.
 */
@Composable
private fun DatabaseNotAvailableContent(
    onOpenApp: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "Dictionary not available",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.error
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "The dictionary database needs to be downloaded first.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(12.dp))
        TextButton(onClick = onOpenApp) {
            Text("Open Dictionary App to Download")
        }
    }
}

/**
 * Error content.
 */
@Composable
private fun ErrorContent(message: String) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "Error",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.error
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Look up a word in the dictionary.
 *
 * This function handles:
 * - Checking if database exists
 * - Initializing DictCore if needed
 * - Searching for the word
 * - Getting the full definition
 */
private fun lookupWord(context: Context, word: String): QuickDefinitionState {
    // Check if database exists
    val dbFile = File(context.filesDir, "dict.db")
    if (!dbFile.exists() || dbFile.length() == 0L) {
        return QuickDefinitionState.DatabaseNotAvailable
    }

    // Try to initialize DictCore (it might already be initialized by main app)
    // DictCore.init is idempotent - calling it multiple times is safe
    val initResult = DictCore.init(dbFile.absolutePath)
    if (initResult != DictCore.SUCCESS && initResult != DictCore.ERROR_NOT_INITIALIZED) {
        // Check if it's a different error (not just "already initialized")
        // ERROR_NOT_INITIALIZED means we need to init, other errors are real problems
        if (initResult == DictCore.ERROR_INIT_FAILED) {
            return QuickDefinitionState.Error("Failed to open dictionary database")
        }
    }

    return try {
        // Search for the word
        val results = DictCore.searchParsed(word, 1)

        if (results.isEmpty()) {
            // Try searching for the word in lowercase
            val lowercaseResults = DictCore.searchParsed(word.lowercase(), 1)
            if (lowercaseResults.isEmpty()) {
                return QuickDefinitionState.NotFound(word)
            }
            // Use lowercase result
            val definition = DictCore.getDefinitionParsed(lowercaseResults[0].id)
            if (definition != null) {
                QuickDefinitionState.Success(definition)
            } else {
                QuickDefinitionState.NotFound(word)
            }
        } else {
            // Get full definition for the first result
            val definition = DictCore.getDefinitionParsed(results[0].id)
            if (definition != null) {
                QuickDefinitionState.Success(definition)
            } else {
                QuickDefinitionState.NotFound(word)
            }
        }
    } catch (e: Exception) {
        QuickDefinitionState.Error(e.message ?: "Unknown error occurred")
    }
}
