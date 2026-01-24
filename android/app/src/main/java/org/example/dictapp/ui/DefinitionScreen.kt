package org.example.dictapp.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

import org.example.dictapp.Definition
import org.example.dictapp.FullDefinition
import org.example.dictapp.viewmodel.DefinitionState
import org.example.dictapp.viewmodel.DictViewModel

/**
 * Screen displaying the full definition of a word.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DefinitionScreen(
    wordId: Long,
    viewModel: DictViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val definitionState by viewModel.definitionState.collectAsState()

    // Fallback: load definition if not already pre-loaded by click handler
    LaunchedEffect(wordId) {
        if (viewModel.definitionState.value is DefinitionState.Idle) {
            viewModel.loadDefinition(wordId)
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    when (val state = definitionState) {
                        is DefinitionState.Success -> Text(state.definition.word)
                        else -> Text("Definition")
                    }
                },
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.testTag(TestTags.BACK_BUTTON)
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                },
                actions = {
                    when (val state = definitionState) {
                        is DefinitionState.Success -> {
                            if (state.definition.langCode.isNotEmpty()) {
                                Text(
                                    text = state.definition.langCode,
                                    style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                                    modifier = Modifier.padding(end = 16.dp)
                                )
                            }
                        }
                        else -> {}
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .testTag(TestTags.DEFINITION_SCREEN)
        ) {
            when (val state = definitionState) {
                is DefinitionState.Loading -> {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .align(Alignment.Center)
                            .testTag(TestTags.LOADING_INDICATOR)
                    )
                }

                is DefinitionState.Success -> {
                    DefinitionContent(
                        definition = state.definition,
                        modifier = Modifier.testTag(TestTags.DEFINITION_CONTENT)
                    )
                }

                is DefinitionState.Error -> {
                    Text(
                        text = state.message,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.align(Alignment.Center)
                    )
                }

                is DefinitionState.Idle -> {
                    // Initial state, loading will start
                }
            }
        }
    }
}

/**
 * Content displaying all parts of a word definition.
 */
@Composable
private fun DefinitionContent(
    definition: FullDefinition,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp)
    ) {
        // Header with word and pronunciation
        item {
            WordHeader(definition = definition)
            Spacer(modifier = Modifier.height(16.dp))
        }

        // Etymology (if available)
        definition.etymology?.let { etymology ->
            item {
                EtymologySection(
                    etymology = etymology,
                    modifier = Modifier.testTag(TestTags.ETYMOLOGY_SECTION)
                )
                Spacer(modifier = Modifier.height(16.dp))
            }
        }

        // Definitions list
        item {
            Text(
                text = "Definitions",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.testTag(TestTags.DEFINITIONS_SECTION)
            )
            Spacer(modifier = Modifier.height(8.dp))
        }

        itemsIndexed(definition.definitions) { index, def ->
            DefinitionCard(
                index = index + 1,
                definition = def,
                modifier = Modifier.testTag("${TestTags.DEFINITION_CARD}_$index")
            )
            Spacer(modifier = Modifier.height(8.dp))
        }

        // Translations (if available)
        if (definition.translations.isNotEmpty()) {
            item {
                Spacer(modifier = Modifier.height(16.dp))
                TranslationsSection(
                    translations = definition.translations,
                    modifier = Modifier.testTag(TestTags.TRANSLATIONS_SECTION)
                )
            }
        }
    }
}

/**
 * Header section with word, part of speech, and pronunciation.
 */
@Composable
private fun WordHeader(
    definition: FullDefinition,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .testTag(TestTags.DEFINITION_HEADER),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            // Word and part of speech
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = definition.word,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.testTag(TestTags.DEFINITION_WORD)
                )

                Spacer(modifier = Modifier.width(12.dp))

                AdaptivePartOfSpeech(
                    pos = definition.pos,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                    modifier = Modifier.testTag(TestTags.DEFINITION_POS)
                )
            }

            // Pronunciations
            if (definition.pronunciations.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))

                definition.pronunciations.forEach { pronunciation ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        pronunciation.ipa?.let { ipa ->
                            Text(
                                text = "/$ipa/",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.9f)
                            )
                        }

                        pronunciation.accent?.let { accent ->
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "($accent)",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                            )
                        }

                        // Audio button (placeholder - actual audio playback to be implemented)
                        pronunciation.audioUrl?.let {
                            Spacer(modifier = Modifier.width(8.dp))
                            IconButton(onClick = { /* TODO: Play audio */ }) {
                                Icon(
                                    imageVector = Icons.Default.VolumeUp,
                                    contentDescription = "Play pronunciation",
                                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                                )
                            }
                        }
                    }
                }
            }


        }
    }
}

/**
 * Etymology section.
 */
@Composable
private fun EtymologySection(
    etymology: String,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Text(
                text = "Etymology",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = etymology,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Card for a single definition with examples and tags.
 */
@Composable
private fun DefinitionCard(
    index: Int,
    definition: Definition,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            // Definition text with number
            Text(
                text = "$index. ${definition.text}",
                style = MaterialTheme.typography.bodyLarge
            )

            // Tags
            if (definition.tags.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Row {
                    definition.tags.take(5).forEach { tag ->
                        SuggestionChip(
                            onClick = { },
                            label = {
                                Text(
                                    text = tag,
                                    style = MaterialTheme.typography.labelSmall
                                )
                            },
                            modifier = Modifier.padding(end = 4.dp)
                        )
                    }
                }
            }

            // Examples
            if (definition.examples.isNotEmpty()) {
                Spacer(modifier = Modifier.height(12.dp))
                HorizontalDivider()
                Spacer(modifier = Modifier.height(8.dp))

                Text(
                    text = "Examples",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Spacer(modifier = Modifier.height(4.dp))

                definition.examples.forEach { example ->
                    Text(
                        text = "• \"$example\"",
                        style = MaterialTheme.typography.bodyMedium,
                        fontStyle = FontStyle.Italic,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 2.dp)
                    )
                }
            }
        }
    }
}

/**
 * Section showing translations.
 */
@Composable
private fun TranslationsSection(
    translations: List<org.example.dictapp.Translation>,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Text(
            text = "Translations",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                translations.take(10).forEach { translation ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp)
                    ) {
                        Text(
                            text = translation.targetLanguage,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.width(100.dp)
                        )

                        Text(
                            text = translation.translation,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }

                if (translations.size > 10) {
                    Text(
                        text = "+${translations.size - 10} more translations",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
            }
        }
    }
}
