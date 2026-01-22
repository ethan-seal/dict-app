package org.example.dictapp.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.example.dictapp.settings.EnglishVariant
import org.example.dictapp.settings.SettingsRepository

/**
 * Settings screen with app preferences.
 * 
 * @param onBack Navigation callback to return to previous screen
 * @param onNavigateToDesignSystem Navigation callback to design system showcase
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onNavigateToDesignSystem: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val settingsRepository = SettingsRepository(context)
    val englishVariant by settingsRepository.englishVariant.collectAsState(initial = EnglishVariant.NONE)
    val coroutineScope = rememberCoroutineScope()
    
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.testTag(TestTags.SETTINGS_BACK_BUTTON)
                    ) {
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .verticalScroll(rememberScrollState())
                .testTag(TestTags.SETTINGS_SCREEN)
        ) {
            // Language Preferences Section
            SettingsSectionHeader(title = "Language Preferences")
            
            EnglishVariantSelector(
                selectedVariant = englishVariant,
                onVariantSelected = { variant ->
                    coroutineScope.launch {
                        settingsRepository.setEnglishVariant(variant)
                    }
                }
            )
            
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            
            // Developer Section
            SettingsSectionHeader(title = "Developer")
            
            NavigationSettingsItem(
                title = "Design System Showcase",
                subtitle = "View UI components and theme colors",
                onClick = onNavigateToDesignSystem,
                modifier = Modifier.testTag(TestTags.SETTINGS_DESIGN_SYSTEM_ITEM)
            )
            
            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

/**
 * Section header for grouping related settings.
 */
@Composable
private fun SettingsSectionHeader(
    title: String,
    modifier: Modifier = Modifier
) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    )
}

/**
 * English variant selection with radio buttons.
 */
@Composable
private fun EnglishVariantSelector(
    selectedVariant: EnglishVariant,
    onVariantSelected: (EnglishVariant) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .selectableGroup()
            .testTag(TestTags.SETTINGS_ENGLISH_VARIANT_SELECTOR)
    ) {
        Text(
            text = "English Variant",
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )
        
        Text(
            text = "Prefer pronunciations and spellings from a specific English variant",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
        )
        
        Spacer(modifier = Modifier.height(8.dp))
        
        EnglishVariant.entries.forEach { variant ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = selectedVariant == variant,
                        onClick = { onVariantSelected(variant) },
                        role = Role.RadioButton
                    )
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                RadioButton(
                    selected = selectedVariant == variant,
                    onClick = null // Handled by row's selectable modifier
                )
                
                Spacer(modifier = Modifier.width(12.dp))
                
                Text(
                    text = variant.displayName,
                    style = MaterialTheme.typography.bodyLarge
                )
            }
        }
    }
}

/**
 * Navigation item that leads to another screen.
 */
@Composable
private fun NavigationSettingsItem(
    title: String,
    subtitle: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge
            )
            
            subtitle?.let {
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
