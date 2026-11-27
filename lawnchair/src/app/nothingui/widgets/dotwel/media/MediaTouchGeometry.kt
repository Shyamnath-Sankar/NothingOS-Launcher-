package app.nothingui.widgets.dotwel.media

/** Same logical design-space centers used by MediaRenderers, mapped to each host. */
object MediaTouchGeometry {
    data class Box(val left: Float, val top: Float, val right: Float, val bottom: Float)
    data class Controls(val previous: Box?, val play: Box?, val next: Box?, val clear: Box? = null, val volumeUp: Box? = null, val volumeDown: Box? = null)
    fun design(kind: MediaWidgetKind): Controls {
        val w = kind.designWidth
        val h = kind.designHeight
        fun box(x: Float, y: Float, size: Float) = Box(x - size / 2, y - size / 2, x + size / 2, y + size / 2)
        fun row(x: Float, y: Float, play: Float, skip: Float, gap: Float) = Controls(box(x - gap, y, skip * 1.5f), box(x, y, play * 1.5f), box(x + gap, y, skip * 1.5f))
        return when (kind) {
            MediaWidgetKind.M3_EXPANDED, MediaWidgetKind.M3_OUTPUT -> row(w / 2, h - 66, 54f, 40f, 130f)
            MediaWidgetKind.MINI -> Controls(box(40f, h - 40, 48f), box(96f, h - 40, 60f), box(152f, h - 40, 48f))
            MediaWidgetKind.MINIMAL, MediaWidgetKind.MINIMAL_2, MediaWidgetKind.MINIMAL_3 -> row(w - 144, h / 2, 48f, 34f, 78f)
            MediaWidgetKind.NOTHING_MASTER -> row(w / 2, h * .92f, 58f, 40f, 140f)
            MediaWidgetKind.NOTHING_PLAYER -> row(w / 2, h * .58f, 76f, 46f, 160f)
            MediaWidgetKind.NOTHING_PLAYER_2 -> Controls(null, box(w * .86f, h / 2, 84f), null)
            MediaWidgetKind.NOTHING_PLAYER_3 -> row(w / 2, h * .76f, 74f, 46f, 132f).copy(volumeUp = box(w * .30f - w / 6, h * .42f, 44f), volumeDown = box(w * .30f + w / 6, h * .42f, 44f))
            MediaWidgetKind.UNIVERSAL -> row(w - 190, 360f, 58f, 40f, 86f)
            MediaWidgetKind.NOTIFICATION -> Controls(null, null, null, Box(w - 210, h - 78, w - 34, h - 28))
        }
    }
    fun map(box: Box, kind: MediaWidgetKind, width: Float, height: Float): Box {
        val scale = minOf(width / kind.designWidth, height / kind.designHeight)
        val x = (width - kind.designWidth * scale) / 2
        val y = (height - kind.designHeight * scale) / 2
        return Box(x + box.left * scale, y + box.top * scale, x + box.right * scale, y + box.bottom * scale)
    }
}
