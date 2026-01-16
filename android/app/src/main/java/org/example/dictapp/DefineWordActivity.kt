package org.example.dictapp

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
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
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.example.dictapp.ui.theme.DictAppTheme

/**
 * Activity that handles ACTION_PROCESS_TEXT intent for quick word lookup.
 *
 * When the user selects text in any app and chooses "Define" from the context menu,
 * this activity shows a dialog with the word definition.
 */
class DefineWordActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val selectedText = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            ?.toString()
            ?.trim()

        if (selectedText.isNullOrBlank()) {
            finish()
            return
        }

        setContent {
            DictAppTheme {
                QuickDefinitionDialog(
                    word = selectedText,
                    onDismiss = { finish() }
                )
            }
        }
    }
}

/**
 * Quick definition dialog shown when text is selected.
 */
@Composable
fun QuickDefinitionDialog(
    word: String,
    onDismiss: () -> Unit
) {
    var isLoading by remember { mutableStateOf(true) }
    var definition by remember { mutableStateOf<FullDefinition?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    // Search for the word
    LaunchedEffect(word) {
        isLoading = true
        error = null

        withContext(Dispatchers.IO) {
            try {
                // First search for the word
                val results = DictCore.searchParsed(word, 1)
                if (results.isNotEmpty()) {
                    // Get full definition for the first result
                    definition = DictCore.getDefinitionParsed(results[0].id)
                    if (definition == null) {
                        error = "Definition not found"
                    }
                } else {
                    error = "Word not found: \"$word\""
                }
            } catch (e: Exception) {
                error = "Error: ${e.message}"
            }
            isLoading = false
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
                // Title
                Text(
                    text = word,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )

                Spacer(modifier = Modifier.height(16.dp))

                when {
                    isLoading -> {
                        CircularProgressIndicator(
                            modifier = Modifier.align(Alignment.CenterHorizontally)
                        )
                    }

                    error != null -> {
                        Text(
                            text = error!!,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error
                        )
                    }

                    definition != null -> {
                        QuickDefinitionContent(definition = definition!!)
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Dismiss button
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.align(Alignment.End)
                ) {
                    Text("Close")
                }
            }
        }
    }
}

/**
 * Content for the quick definition dialog.
 */
@Composable
private fun QuickDefinitionContent(
    definition: FullDefinition,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
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

        // Show count if there are more definitions
        if (definition.definitions.size > 3) {
            Text(
                text = "+${definition.definitions.size - 3} more definitions",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp)
            )
        }
    }
}
