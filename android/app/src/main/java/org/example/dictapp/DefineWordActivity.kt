package org.example.dictapp

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import org.example.dictapp.ui.QuickDefinitionDialog
import org.example.dictapp.ui.theme.DictAppTheme

/**
 * Activity that handles ACTION_PROCESS_TEXT intent for quick word lookup.
 *
 * When the user selects text in any app and chooses "Define" from the context menu,
 * this activity shows a dialog with the word definition.
 *
 * Features:
 * - Receives selected text from Intent.EXTRA_PROCESS_TEXT
 * - Shows a compact dialog with the word definition
 * - Uses DictCore to look up the word
 * - Handles cases where database doesn't exist
 * - Provides "See more" option to open the full app
 *
 * The activity uses a dialog theme (Theme.DictApp.Dialog) with a translucent
 * background so it appears as an overlay.
 */
class DefineWordActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Get the selected text from the intent
        val selectedText = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            ?.toString()
            ?.trim()
            // Handle multi-word selection by taking first word
            ?.split(Regex("\\s+"))
            ?.firstOrNull()
            ?.trim()

        // If no text was selected, finish the activity
        if (selectedText.isNullOrBlank()) {
            finish()
            return
        }

        setContent {
            DictAppTheme {
                QuickDefinitionDialog(
                    word = selectedText,
                    onDismiss = { finish() },
                    onOpenFullApp = { word ->
                        openMainApp(word)
                    }
                )
            }
        }
    }

    /**
     * Open the main app, optionally with a search query.
     */
    private fun openMainApp(word: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            // Pass the word as an extra so the main app can search for it
            putExtra(EXTRA_SEARCH_WORD, word)
            // Clear any existing task and start fresh
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(intent)
        // Finish this activity after launching main app
        finish()
    }

    companion object {
        /**
         * Extra key for passing a word to search in MainActivity.
         */
        const val EXTRA_SEARCH_WORD = "extra_search_word"
    }
}
