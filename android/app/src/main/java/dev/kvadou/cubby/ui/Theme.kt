package dev.kvadou.cubby.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// The web app's palette (web/src/styles.css): forest green on warm paper.
private val Light = lightColorScheme(
    primary = Color(0xFF2F6B4F),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE4EFE8),
    onPrimaryContainer = Color(0xFF173B2A),
    secondaryContainer = Color(0xFFDCE9E0),
    onSecondaryContainer = Color(0xFF173B2A),
    background = Color(0xFFF7F5F0),
    onBackground = Color(0xFF1D2420),
    surface = Color(0xFFF7F5F0),
    onSurface = Color(0xFF1D2420),
    surfaceContainer = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFECE8DF),
    onSurfaceVariant = Color(0xFF5C6862),
    outlineVariant = Color(0xFFE3DFD5),
    error = Color(0xFFA8262F),
)

private val Dark = darkColorScheme(
    primary = Color(0xFF8FD1AE),
    onPrimary = Color(0xFF00391F),
    primaryContainer = Color(0xFF1F4A35),
    onPrimaryContainer = Color(0xFFCDEBD9),
    secondaryContainer = Color(0xFF2A3A31),
    onSecondaryContainer = Color(0xFFCDEBD9),
    background = Color(0xFF121512),
    onBackground = Color(0xFFE3E6E1),
    surface = Color(0xFF121512),
    onSurface = Color(0xFFE3E6E1),
    surfaceContainer = Color(0xFF1C201C),
    surfaceContainerLow = Color(0xFF1C201C),
    surfaceVariant = Color(0xFF2A2F2A),
    onSurfaceVariant = Color(0xFFB9C2BB),
    outlineVariant = Color(0xFF3A403B),
    error = Color(0xFFFFB3B0),
)

@Composable
fun CubbyTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) Dark else Light, content = content)
}
