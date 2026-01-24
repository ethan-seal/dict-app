package org.example.dictapp.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

// Color palette - derived from a book/dictionary theme
private val LightPrimary = Color(0xFF5D4037)        // Brown
private val LightOnPrimary = Color(0xFFFFFFFF)
private val LightPrimaryContainer = Color(0xFFD7CCC8) // Light brown
private val LightOnPrimaryContainer = Color(0xFF3E2723)
private val LightSecondary = Color(0xFF795548)       // Medium brown
private val LightOnSecondary = Color(0xFFFFFFFF)
private val LightSecondaryContainer = Color(0xFFBCAAA4)
private val LightOnSecondaryContainer = Color(0xFF3E2723)
private val LightTertiary = Color(0xFF607D8B)        // Blue gray
private val LightOnTertiary = Color(0xFFFFFFFF)
private val LightTertiaryContainer = Color(0xFFCFD8DC)
private val LightOnTertiaryContainer = Color(0xFF263238)
private val LightError = Color(0xFFB00020)
private val LightOnError = Color(0xFFFFFFFF)
private val LightErrorContainer = Color(0xFFFCD8DF)
private val LightOnErrorContainer = Color(0xFF8C0016)
private val LightBackground = Color(0xFFFFFBF8)      // Warm white (paper-like)
private val LightOnBackground = Color(0xFF1C1B1F)
private val LightSurface = Color(0xFFFFFBF8)
private val LightOnSurface = Color(0xFF1C1B1F)
private val LightSurfaceVariant = Color(0xFFEFEBE9)
private val LightOnSurfaceVariant = Color(0xFF3D3843)
private val LightOutline = Color(0xFF79747E)
private val LightSurfaceContainerLow = Color(0xFFF7F2EF)

private val DarkPrimary = Color(0xFFBCAAA4)          // Light brown
private val DarkOnPrimary = Color(0xFF3E2723)
private val DarkPrimaryContainer = Color(0xFF5D4037)
private val DarkOnPrimaryContainer = Color(0xFFD7CCC8)
private val DarkSecondary = Color(0xFFD7CCC8)
private val DarkOnSecondary = Color(0xFF3E2723)
private val DarkSecondaryContainer = Color(0xFF5D4037)
private val DarkOnSecondaryContainer = Color(0xFFD7CCC8)
private val DarkTertiary = Color(0xFFB0BEC5)
private val DarkOnTertiary = Color(0xFF263238)
private val DarkTertiaryContainer = Color(0xFF455A64)
private val DarkOnTertiaryContainer = Color(0xFFCFD8DC)
private val DarkError = Color(0xFFCF6679)
private val DarkOnError = Color(0xFF000000)
private val DarkErrorContainer = Color(0xFF8C0016)
private val DarkOnErrorContainer = Color(0xFFFCD8DF)
private val DarkBackground = Color(0xFF1C1B1F)
private val DarkOnBackground = Color(0xFFE6E1E5)
private val DarkSurface = Color(0xFF1C1B1F)
private val DarkOnSurface = Color(0xFFE6E1E5)
private val DarkSurfaceVariant = Color(0xFF3E2723)
private val DarkOnSurfaceVariant = Color(0xFFCAC4D0)
private val DarkOutline = Color(0xFF938F99)
private val DarkSurfaceContainerLow = Color(0xFF252329)

private val LightColorScheme = lightColorScheme(
    primary = LightPrimary,
    onPrimary = LightOnPrimary,
    primaryContainer = LightPrimaryContainer,
    onPrimaryContainer = LightOnPrimaryContainer,
    secondary = LightSecondary,
    onSecondary = LightOnSecondary,
    secondaryContainer = LightSecondaryContainer,
    onSecondaryContainer = LightOnSecondaryContainer,
    tertiary = LightTertiary,
    onTertiary = LightOnTertiary,
    tertiaryContainer = LightTertiaryContainer,
    onTertiaryContainer = LightOnTertiaryContainer,
    error = LightError,
    onError = LightOnError,
    errorContainer = LightErrorContainer,
    onErrorContainer = LightOnErrorContainer,
    background = LightBackground,
    onBackground = LightOnBackground,
    surface = LightSurface,
    onSurface = LightOnSurface,
    surfaceVariant = LightSurfaceVariant,
    onSurfaceVariant = LightOnSurfaceVariant,
    outline = LightOutline,
    surfaceContainerLow = LightSurfaceContainerLow
)

private val DarkColorScheme = darkColorScheme(
    primary = DarkPrimary,
    onPrimary = DarkOnPrimary,
    primaryContainer = DarkPrimaryContainer,
    onPrimaryContainer = DarkOnPrimaryContainer,
    secondary = DarkSecondary,
    onSecondary = DarkOnSecondary,
    secondaryContainer = DarkSecondaryContainer,
    onSecondaryContainer = DarkOnSecondaryContainer,
    tertiary = DarkTertiary,
    onTertiary = DarkOnTertiary,
    tertiaryContainer = DarkTertiaryContainer,
    onTertiaryContainer = DarkOnTertiaryContainer,
    error = DarkError,
    onError = DarkOnError,
    errorContainer = DarkErrorContainer,
    onErrorContainer = DarkOnErrorContainer,
    background = DarkBackground,
    onBackground = DarkOnBackground,
    surface = DarkSurface,
    onSurface = DarkOnSurface,
    surfaceVariant = DarkSurfaceVariant,
    onSurfaceVariant = DarkOnSurfaceVariant,
    outline = DarkOutline,
    surfaceContainerLow = DarkSurfaceContainerLow
)

/**
 * Main theme for the Dictionary App.
 *
 * Uses Material 3 theming with a warm, book-inspired color palette.
 * Supports both light and dark themes, with dynamic colors on Android 12+.
 *
 * @param darkTheme Whether to use dark theme
 * @param dynamicColor Whether to use dynamic colors (Android 12+)
 * @param content The composable content
 */
@Composable
fun DictAppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.primaryContainer.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}

// Typography customization
private val Typography = androidx.compose.material3.Typography()
