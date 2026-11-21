package app.lawnchair.gestures.config

import android.app.Activity
import android.content.Context

val gestureHandlerOptions = listOf(
    GestureHandlerOption.NoOp,
    GestureHandlerOption.Sleep,
    GestureHandlerOption.Recents,
    GestureHandlerOption.OpenNotifications,
    GestureHandlerOption.OpenQuickSettings,
    GestureHandlerOption.OpenAppDrawer,
    GestureHandlerOption.OpenAppSearch,
    GestureHandlerOption.OpenSearch,
    GestureHandlerOption.OpenApp,
    GestureHandlerOption.OpenAssistant,
)

private val optionsDisabledInDeckLayout = setOf(
    GestureHandlerOption.OpenAppDrawer,
    GestureHandlerOption.OpenAppSearch,
)

// These handlers either require the accessibility service or fall back to it.
// Play builds do not declare the service (AGENTS.md section 7), so surfacing
// them there would only lead to a settings screen that cannot enable anything.
private val accessibilityOptions = setOf(
    GestureHandlerOption.Recents,
    GestureHandlerOption.OpenNotifications,
    GestureHandlerOption.OpenQuickSettings,
)

fun filterGestureHandlerOptions(
    deckLayoutEnabled: Boolean,
    accessibilityEnabled: Boolean = true,
): List<GestureHandlerOption> {
    return gestureHandlerOptions
        .filter { accessibilityEnabled || it !in accessibilityOptions }
        .filter { !deckLayoutEnabled || it !in optionsDisabledInDeckLayout }
}

suspend fun GestureHandlerOption.buildConfigFrom(context: Context): GestureHandlerConfig? {
    val activity = context as? Activity ?: return null
    return buildConfig(activity)
}
