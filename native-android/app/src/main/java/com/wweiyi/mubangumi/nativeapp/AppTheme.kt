package com.wweiyi.mubangumi.nativeapp

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val BrandPink = Color(0xFFE95383)
val BrandPinkLight = Color(0xFFFFE8EF)
val AppInk = Color(0xFF1D2433)
val AppCanvas = Color(0xFFFBFAF9)

private val LightColors = lightColorScheme(
    primary = BrandPink,
    secondary = Color(0xFF38A89D),
    tertiary = Color(0xFFF3A646),
    background = AppCanvas,
    surface = Color.White,
    surfaceVariant = Color(0xFFF1F1F6),
    onSurface = AppInk,
    outlineVariant = Color(0xFFE5E5EC),
    primaryContainer = BrandPinkLight,
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFFF77A2),
    secondary = Color(0xFFA99AF7),
    tertiary = Color(0xFFF1B654),
    background = Color(0xFF101014),
    surface = Color(0xFF16161E),
    surfaceVariant = Color(0xFF23232F),
    outlineVariant = Color(0xFF343442),
    primaryContainer = Color(0xFF4A1F31),
)

private val AppTypography = Typography(
    headlineLarge = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.8).sp),
    headlineMedium = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    titleLarge = TextStyle(fontSize = 21.sp, fontWeight = FontWeight.Bold),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 21.sp),
)

val AppCardShape = RoundedCornerShape(14)
val AppFieldShape = RoundedCornerShape(16)

@Composable
fun MuBangumiTheme(darkMode: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkMode) DarkColors else LightColors,
        typography = AppTypography,
        shapes = MaterialTheme.shapes.copy(medium = AppCardShape, large = AppFieldShape),
        content = content,
    )
}
