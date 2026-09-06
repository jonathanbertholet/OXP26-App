package be.oxp.app

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

fun cardTags(talk: Talk) = talk.tags.sortedBy {
    when (it.category) { "Topics" -> 0; "Audience" -> 1; "Tracks" -> 2; "Speaker" -> 3; else -> 4 }
}.distinctBy { it.id }

/** Topic chips and card accents share a stable, named palette across rooms. */
fun topicColor(name: String): Color = Color(when (name) {
    "Accounting & Finance", "Accounting" -> 0xFF257D72
    "Logistic & Manufacturing", "Manufacturing" -> 0xFF99651F
    "Marketing & eCommerce", "Website & eCommerce" -> 0xFFB24775
    "Artificial Intelligence", "AI" -> 0xFF8052B4
    "Sales" -> 0xFF4D7D36
    "Human Resource", "Human Resources" -> 0xFFB55B42
    "Retail & Food", "Retail" -> 0xFFA2642C
    "Productivity & Project", "Services" -> 0xFF426FAB
    else -> 0xFF714B67
})

fun talkAccent(talk: Talk): Color {
    val topic = talk.tags.firstOrNull { it.category == "Topics" } ?: talk.tags.firstOrNull { it.category == "Tracks" }
    if (topic != null) return topicColor(topic.name)
    return when (talk.kind) {
        "keynote", "opening" -> OxpPlum
        "masterclass" -> Color(0xFF99651F)
        "break" -> Color(0xFF6B7C79)
        "social" -> OxpRose
        else -> roomColor(talk.location)
    }
}

private fun shortTag(name: String) = when (name) {
    "Accounting & Finance" -> "Accounting"
    "Logistic & Manufacturing" -> "Logistics & Mfg"
    "Marketing & eCommerce" -> "Marketing"
    "Artificial Intelligence" -> "AI"
    "Productivity & Project" -> "Productivity"
    "Odoo Beginners" -> "Beginners"
    "Odoo Experts" -> "Experts"
    "Students & Teachers" -> "Education"
    else -> name
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TalkTags(talk: Talk, compact: Boolean = false) {
    val tags = cardTags(talk)
    if (tags.isEmpty()) return
    if (compact) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            tags.take(2).forEach { tag -> TagPill(tag, shortTag(tag.name), Modifier.weight(1f, fill = false)) }
            if (tags.size > 2) Text("+${tags.size - 2}", Modifier.padding(vertical = 3.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    } else {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            tags.forEach { tag -> TagPill(tag, tag.name) }
        }
    }
}

@Composable
private fun TagPill(tag: Tag, title: String, modifier: Modifier = Modifier) {
    val topic = tag.category == "Topics" || tag.category == "Tracks"
    val rawTint = if (topic) topicColor(tag.name) else MaterialTheme.colorScheme.onSurfaceVariant
    val tint = if (topic && isSystemInDarkTheme()) lerp(rawTint, Color.White, .4f) else rawTint
    Text(title, modifier.background(tint.copy(alpha = .1f), RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 3.dp), style = MaterialTheme.typography.labelSmall, color = tint, maxLines = 1, overflow = TextOverflow.Ellipsis)
}
