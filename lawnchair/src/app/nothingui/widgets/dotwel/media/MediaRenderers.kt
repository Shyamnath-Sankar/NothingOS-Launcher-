package app.nothingui.widgets.dotwel.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import app.nothingui.widgets.dotwel.WidgetStyle
import kotlin.math.min

enum class MediaWidgetKind(
    val designWidth: Float,
    val designHeight: Float,
) {
    M3_EXPANDED(918f, 542f),
    M3_OUTPUT(916f, 542f),
    MINI(667f, 542f),
    MINIMAL(918f, 228f),
    MINIMAL_2(918f, 228f),
    MINIMAL_3(918f, 228f),
    NOTHING_MASTER(916f, 1169f),
    NOTHING_PLAYER(916f, 542f),
    NOTHING_PLAYER_2(916f, 226f),
    NOTHING_PLAYER_3(415f, 542f),
    UNIVERSAL(918f, 542f),
    NOTIFICATION(916f, 226f),
}

/**
 * Draws the reference media-controls card for every existing media kind. The
 * previous per-preset layouts are intentionally replaced so the family matches
 * the reference white card, red dot-matrix artist, black dot-matrix title and
 * top-right play/pause glyph. Real session data, cover art and transport state
 * are unchanged; nothing is invented.
 */
object MediaRenderers {
    fun render(
        context: Context,
        kind: MediaWidgetKind,
        width: Int,
        height: Int,
        style: WidgetStyle,
        snapshot: MediaSnapshot,
    ): Bitmap {
        val safeWidth = width.coerceAtLeast(2)
        val safeHeight = height.coerceAtLeast(2)
        val bitmap = Bitmap.createBitmap(safeWidth, safeHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val scale = min(
            safeWidth / kind.designWidth,
            safeHeight / kind.designHeight,
        ).coerceAtLeast(0.01f)
        val offsetX = (safeWidth - kind.designWidth * scale) / 2f
        val offsetY = (safeHeight - kind.designHeight * scale) / 2f
        canvas.save()
        canvas.translate(offsetX, offsetY)
        canvas.scale(scale, scale)
        ReferenceMediaCard.draw(canvas, kind, snapshot)
        canvas.restore()
        return bitmap
    }
}
