package org.example.dictapp.ui

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.rememberTextMeasurer

/**
 * Mapping of abbreviated parts of speech to their full names.
 */
object PartOfSpeechMapping {
    private val abbreviationToFull = mapOf(
        "n" to "noun",
        "v" to "verb",
        "adj" to "adjective",
        "adv" to "adverb",
        "prep" to "preposition",
        "conj" to "conjunction",
        "pron" to "pronoun",
        "interj" to "interjection",
        "det" to "determiner",
        "num" to "numeral",
        "art" to "article",
        "part" to "particle",
        "aux" to "auxiliary",
        "abbr" to "abbreviation",
        "pref" to "prefix",
        "suf" to "suffix",
        "sym" to "symbol",
        "phrase" to "phrase",
        "expr" to "expression",
        "idiom" to "idiom",
        "proverb" to "proverb",
        "affix" to "affix",
        "infix" to "infix",
        "circfix" to "circumfix",
        "root" to "root",
        "cont" to "contraction"
    )

    /**
     * Get the full name for a part of speech.
     * Returns the original if no mapping exists or if it's already the full form.
     */
    fun getFullName(pos: String): String {
        val lower = pos.lowercase()
        return abbreviationToFull[lower]?.let { full ->
            // Preserve original capitalization pattern
            if (pos.firstOrNull()?.isUpperCase() == true) {
                full.replaceFirstChar { it.uppercase() }
            } else {
                full
            }
        } ?: pos
    }

    /**
     * Check if there's a full form available for this part of speech.
     */
    fun hasFullForm(pos: String): Boolean {
        return abbreviationToFull.containsKey(pos.lowercase())
    }
}

/**
 * A composable that displays part of speech, using the full name when there's enough space,
 * and falling back to the abbreviation when space is limited.
 *
 * @param pos The part of speech (can be abbreviated or full)
 * @param modifier Modifier for the text
 * @param style Text style to use
 * @param color Text color
 * @param fontStyle Font style (default italic)
 */
@Composable
fun AdaptivePartOfSpeech(
    pos: String,
    modifier: Modifier = Modifier,
    style: TextStyle = LocalTextStyle.current,
    color: Color = Color.Unspecified,
    fontStyle: FontStyle = FontStyle.Italic
) {
    val fullName = remember(pos) { PartOfSpeechMapping.getFullName(pos) }
    val textMeasurer = rememberTextMeasurer()
    val density = LocalDensity.current

    BoxWithConstraints(modifier = modifier) {
        val maxWidthPx = with(density) { maxWidth.toPx() }

        // Measure the full name width
        val fullTextWidth = remember(fullName, style, fontStyle) {
            textMeasurer.measure(
                text = fullName,
                style = style.copy(fontStyle = fontStyle)
            ).size.width.toFloat()
        }

        // Use full name if it fits, otherwise use abbreviation
        val displayText = if (fullTextWidth <= maxWidthPx) {
            fullName
        } else {
            pos
        }

        Text(
            text = displayText,
            style = style,
            color = color,
            fontStyle = fontStyle
        )
    }
}
