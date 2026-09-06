package be.oxp.app

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material.icons.filled.Search
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

val OxpPlum = Color(0xFF714B67)
val OxpRose = Color(0xFFC14D76)

@Composable
fun OxpTheme(content: @Composable () -> Unit) {
    val colors = if (isSystemInDarkTheme()) darkColorScheme(
        primary = Color(0xFFD4AAC7), onPrimary = Color(0xFF382333), primaryContainer = Color(0xFF50394A), onPrimaryContainer = Color(0xFFF2DCEC),
        secondary = Color(0xFF9CCDBD), secondaryContainer = Color(0xFF293E37), onSecondaryContainer = Color(0xFFD6EEE5),
        background = Color(0xFF19171A), onBackground = Color(0xFFF1EDF0), surface = Color(0xFF242125), onSurface = Color(0xFFF1EDF0),
        surfaceVariant = Color(0xFF302C32), onSurfaceVariant = Color(0xFFB9B2BB), surfaceTint = Color.Transparent,
        surfaceContainer = Color(0xFF242125), surfaceContainerLow = Color(0xFF242125), surfaceContainerHighest = Color(0xFF302C32),
        outline = Color(0xFF655D66), outlineVariant = Color(0xFF3C353E)
    ) else lightColorScheme(
        primary = OxpPlum, onPrimary = Color.White, primaryContainer = Color(0xFFEDE4EB), onPrimaryContainer = OxpPlum,
        secondary = Color(0xFF346C60), secondaryContainer = Color(0xFFE3EEE9), onSecondaryContainer = Color(0xFF264F46),
        background = Color(0xFFF4F2F4), onBackground = Color(0xFF211E22), surface = Color.White, onSurface = Color(0xFF211E22),
        surfaceVariant = Color(0xFFEBE8EC), onSurfaceVariant = Color(0xFF756F78), surfaceTint = Color.Transparent,
        surfaceContainer = Color.White, surfaceContainerLow = Color.White, surfaceContainerHighest = Color(0xFFEBE8EC),
        outline = Color(0xFFB7ADB6), outlineVariant = Color(0xFFE7E0E6)
    )
    MaterialTheme(
        colorScheme = colors,
        typography = Typography(
            headlineLarge = TextStyle(fontSize = 30.sp, lineHeight = 35.sp, fontWeight = FontWeight.Bold, letterSpacing = (-.6).sp),
            headlineMedium = TextStyle(fontSize = 26.sp, lineHeight = 32.sp, fontWeight = FontWeight.Bold, letterSpacing = (-.4).sp),
            titleLarge = TextStyle(fontSize = 21.sp, lineHeight = 27.sp, fontWeight = FontWeight.Bold, letterSpacing = (-.3).sp),
            titleMedium = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold),
            labelLarge = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold)
        ),
        content = content
    )
}

/** Same room palette as OxpTheme.swift. */
fun roomColor(room: String?): Color = Color(when (room) {
    "Hall 6.A" -> 0xFFBF5459; "Hall 6.B" -> 0xFFDB8538; "Hall 6.C" -> 0xFF338C7A
    "Hall 6.D" -> 0xFF5473B8; "Hall 6.E" -> 0xFF8C61B3
    "Hall 7.A" -> 0xFF2E789E; "Hall 7.B" -> 0xFF9E477A
    "Auditorium 4000 A", "Main stage" -> 0xFF733866; "Auditorium 4000 B" -> 0xFF854775
    "Auditorium 4000 C" -> 0xFF945280; "Auditorium 4000 D" -> 0xFFA35C8A
    "Auditorium 2000 A", "Auditorium 2000" -> 0xFF386194; "Auditorium 2000 B" -> 0xFF4270A3
    "Auditorium 2000 C" -> 0xFF4D80B3; "Auditorium 500" -> 0xFF66946B
    "Education Village" -> 0xFF2E9485; else -> 0xFF714B67
})

@Composable
fun OxpChip(selected: Boolean, onClick: () -> Unit, label: @Composable () -> Unit) {
    FilterChip(
        selected = selected, onClick = onClick, label = label,
        shape = RoundedCornerShape(50), border = BorderStroke(0.dp, Color.Transparent),
        colors = FilterChipDefaults.filterChipColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
            labelColor = MaterialTheme.colorScheme.onSurface,
            selectedContainerColor = OxpPlum, selectedLabelColor = Color.White
        )
    )
}

@Composable
fun OxpSearch(query: String, change: (String) -> Unit, hint: String, modifier: Modifier = Modifier) {
    TextField(query, change, modifier.fillMaxWidth(), singleLine = true,
        placeholder = { Text(hint, style = MaterialTheme.typography.bodyMedium) },
        leadingIcon = { androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Default.Search, null, Modifier.size(20.dp)) },
        shape = RoundedCornerShape(28.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent
        )
    )
}
