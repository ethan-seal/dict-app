package org.example.dictapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Design System showcase screen for developer reference.
 *
 * Displays all UI components, colors, typography, and patterns used in the app.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DesignSystemScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Design System") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // 1. Color Palette
            item { SectionHeader("Color Palette") }
            item { ColorPaletteSection() }

            // 2. Typography
            item { SectionHeader("Typography") }
            item { TypographySection() }

            // 3. Buttons
            item { SectionHeader("Buttons") }
            item { ButtonsSection() }

            // 4. Cards
            item { SectionHeader("Cards") }
            item { CardsSection() }

            // 5. Input Fields
            item { SectionHeader("Input Fields") }
            item { InputFieldsSection() }

            // 6. Chips
            item { SectionHeader("Chips") }
            item { ChipsSection() }

            // 7. Icons
            item { SectionHeader("Icons") }
            item { IconsSection() }

            // 8. Progress Indicators
            item { SectionHeader("Progress Indicators") }
            item { ProgressSection() }

            // 9. Layout Patterns
            item { SectionHeader("Layout Patterns") }
            item { LayoutPatternsSection() }

            // 10. States
            item { SectionHeader("States") }
            item { StatesSection() }

            // Bottom spacing
            item { Spacer(modifier = Modifier.height(32.dp)) }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 16.dp, bottom = 4.dp)
    )
}

// --- Section 1: Color Palette ---

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ColorPaletteSection() {
    val colors = listOf(
        "Primary" to MaterialTheme.colorScheme.primary,
        "PrimaryContainer" to MaterialTheme.colorScheme.primaryContainer,
        "Secondary" to MaterialTheme.colorScheme.secondary,
        "Tertiary" to MaterialTheme.colorScheme.tertiary,
        "Error" to MaterialTheme.colorScheme.error,
        "Background" to MaterialTheme.colorScheme.background,
        "Surface" to MaterialTheme.colorScheme.surface,
        "SurfaceVariant" to MaterialTheme.colorScheme.surfaceVariant,
        "Outline" to MaterialTheme.colorScheme.outline,
    )

    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        colors.forEach { (name, color) ->
            ColorSwatch(name = name, color = color)
        }
    }
}

@Composable
private fun ColorSwatch(name: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(color)
                .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(8.dp))
        )
        Text(
            text = name,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(top = 2.dp)
        )
    }
}

// --- Section 2: Typography ---

@Composable
private fun TypographySection() {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("headlineMedium", style = MaterialTheme.typography.headlineMedium)
        Text("headlineSmall", style = MaterialTheme.typography.headlineSmall)
        Text("titleLarge", style = MaterialTheme.typography.titleLarge)
        Text("titleMedium", style = MaterialTheme.typography.titleMedium)
        Text("titleSmall", style = MaterialTheme.typography.titleSmall)
        Text("bodyLarge", style = MaterialTheme.typography.bodyLarge)
        Text("bodyMedium", style = MaterialTheme.typography.bodyMedium)
        Text("bodySmall", style = MaterialTheme.typography.bodySmall)
        Text("labelLarge", style = MaterialTheme.typography.labelLarge)
        Text("labelMedium", style = MaterialTheme.typography.labelMedium)
        Text("labelSmall", style = MaterialTheme.typography.labelSmall)

        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Bold variant",
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Bold
        )
        Text(
            "Medium weight variant",
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium
        )
        Text(
            "Italic variant",
            style = MaterialTheme.typography.bodyLarge,
            fontStyle = FontStyle.Italic
        )
    }
}

// --- Section 3: Buttons ---

@Composable
private fun ButtonsSection() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Filled / Primary", style = MaterialTheme.typography.labelMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = {}) { Text("Download") }
            Button(onClick = {}) { Text("Start Searching") }
        }

        Spacer(modifier = Modifier.height(4.dp))
        Text("Text Buttons", style = MaterialTheme.typography.labelMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = {}) { Text("Cancel") }
            TextButton(onClick = {}) { Text("Close") }
        }

        Spacer(modifier = Modifier.height(4.dp))
        Text("Icon Buttons", style = MaterialTheme.typography.labelMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            IconButton(onClick = {}) {
                Icon(Icons.Filled.Search, contentDescription = "Search")
            }
            IconButton(onClick = {}) {
                Icon(Icons.Filled.Settings, contentDescription = "Settings")
            }
            IconButton(onClick = {}) {
                Icon(Icons.Filled.VolumeUp, contentDescription = "Audio")
            }
        }
    }
}

// --- Section 4: Cards ---

@Composable
private fun CardsSection() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Tonal Card (surfaceContainerLow)", style = MaterialTheme.typography.labelMedium)
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerLow
            )
        ) {
            Text(
                "Card with surfaceContainerLow background",
                modifier = Modifier.padding(16.dp),
                style = MaterialTheme.typography.bodyMedium
            )
        }

        Text("Tonal Card (surfaceVariant)", style = MaterialTheme.typography.labelMedium)
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Text(
                "Card with surfaceVariant background",
                modifier = Modifier.padding(16.dp),
                style = MaterialTheme.typography.bodyMedium
            )
        }

        Text("OutlinedCard (12.dp corners)", style = MaterialTheme.typography.labelMedium)
        OutlinedCard(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Text(
                "Outlined card with rounded corners",
                modifier = Modifier.padding(16.dp),
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

// --- Section 5: Input Fields ---

@Composable
private fun InputFieldsSection() {
    var text by remember { mutableStateOf("") }

    OutlinedTextField(
        value = text,
        onValueChange = { text = it },
        modifier = Modifier.fillMaxWidth(),
        placeholder = { Text("Search for a word...") },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = "Search") },
        trailingIcon = {
            if (text.isNotEmpty()) {
                IconButton(onClick = { text = "" }) {
                    Icon(Icons.Filled.Clear, contentDescription = "Clear")
                }
            }
        },
        singleLine = true
    )
}

// --- Section 6: Chips ---

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChipsSection() {
    val tags = listOf("noun", "verb", "adjective", "adverb", "English", "Latin")

    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        tags.forEach { tag ->
            SuggestionChip(
                onClick = {},
                label = { Text(tag) }
            )
        }
    }
}

// --- Section 7: Icons ---

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun IconsSection() {
    val icons: List<Pair<String, ImageVector>> = listOf(
        "Search" to Icons.Filled.Search,
        "Clear" to Icons.Filled.Clear,
        "Settings" to Icons.Filled.Settings,
        "VolumeUp" to Icons.Filled.VolumeUp,
        "CloudDownload" to Icons.Filled.CloudDownload,
        "Download" to Icons.Filled.Download,
        "CheckCircle" to Icons.Filled.CheckCircle,
        "Language" to Icons.Filled.Language,
        "Error" to Icons.Filled.Error,
        "ArrowBack" to Icons.AutoMirrored.Filled.ArrowBack,
        "ArrowRight" to Icons.AutoMirrored.Filled.KeyboardArrowRight,
    )

    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        icons.forEach { (name, icon) ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    imageVector = icon,
                    contentDescription = name,
                    modifier = Modifier.size(24.dp)
                )
                Text(
                    text = name,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(top = 2.dp)
                )
            }
        }
    }
}

// --- Section 8: Progress Indicators ---

@Composable
private fun ProgressSection() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("CircularProgressIndicator (indeterminate)", style = MaterialTheme.typography.labelMedium)
        CircularProgressIndicator()

        Spacer(modifier = Modifier.height(4.dp))
        Text("LinearProgressIndicator (60%)", style = MaterialTheme.typography.labelMedium)
        LinearProgressIndicator(
            progress = { 0.6f },
            modifier = Modifier.fillMaxWidth()
        )
    }
}

// --- Section 9: Layout Patterns ---

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LayoutPatternsSection() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("TopAppBar sample", style = MaterialTheme.typography.labelMedium)
        TopAppBar(
            title = { Text("Sample Title") },
            navigationIcon = {
                IconButton(onClick = {}) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer,
                titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
            )
        )

        Spacer(modifier = Modifier.height(4.dp))
        Text("HorizontalDivider", style = MaterialTheme.typography.labelMedium)
        HorizontalDivider()

        Spacer(modifier = Modifier.height(4.dp))
        Text("Section header pattern", style = MaterialTheme.typography.labelMedium)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Section Title",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.width(8.dp))
            HorizontalDivider(modifier = Modifier.weight(1f))
        }
    }
}

// --- Section 10: States ---

@Composable
private fun StatesSection() {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // Loading state
        Text("Loading state", style = MaterialTheme.typography.labelMedium)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            Text("Loading definitions...", style = MaterialTheme.typography.bodyMedium)
        }

        // Empty state
        Text("Empty state", style = MaterialTheme.typography.labelMedium)
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Filled.Search,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Search for a word to get started",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Error state
        Text("Error state", style = MaterialTheme.typography.labelMedium)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.Error,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error
            )
            Text(
                text = "Failed to load definition",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error
            )
        }
    }
}
