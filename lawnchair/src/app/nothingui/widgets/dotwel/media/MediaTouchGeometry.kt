package app.nothingui.widgets.dotwel.media

/** Shared logical design-space centres used by ReferenceMediaCard, mapped to each host. */
object MediaTouchGeometry {
    data class Box(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
    )

    data class Controls(
        val previous: Box?,
        val play: Box?,
        val next: Box?,
        val clear: Box? = null,
        val volumeUp: Box? = null,
        val volumeDown: Box? = null,
    )

    fun design(kind: MediaWidgetKind): Controls {
        if (kind == MediaWidgetKind.NOTIFICATION) {
            return Controls(null, null, null, clearBox(kind))
        }
        val controls = ReferenceMediaCard.controlLayout(kind)
        fun box(cx: Float, cy: Float, half: Float) = Box(cx - half, cy - half, cx + half, cy + half)
        if (kind == MediaWidgetKind.UNIVERSAL) {
            val layout = ReferenceMediaCard.universalLayout(kind)
            return Controls(
                previous = null,
                play = box(layout.playCenterX, layout.playCenterY, layout.playRadius * 1.7f),
                next = null,
            )
        }
        val volumeHalf = controls.skipSize * 1.8f
        return Controls(
            previous = box(controls.previousCenterX, controls.centerY, volumeHalf),
            play = box(controls.playCenterX, controls.centerY, controls.playRadius * 1.7f),
            next = box(controls.nextCenterX, controls.centerY, volumeHalf),
            volumeUp = if (kind == MediaWidgetKind.NOTHING_PLAYER_3) {
                box(controls.volumeUpCenterX, controls.volumeCenterY, volumeHalf)
            } else {
                null
            },
            volumeDown = if (kind == MediaWidgetKind.NOTHING_PLAYER_3) {
                box(controls.volumeDownCenterX, controls.volumeCenterY, volumeHalf)
            } else {
                null
            },
        )
    }

    fun clearBox(kind: MediaWidgetKind): Box {
        val width = kind.designWidth
        val height = kind.designHeight
        val side = minOf(width, height)
        return Box(
            width - side * 0.30f,
            height - side * 0.22f,
            width - side * 0.06f,
            height - side * 0.04f,
        )
    }

    fun map(box: Box, kind: MediaWidgetKind, width: Float, height: Float): Box {
        val scale = minOf(width / kind.designWidth, height / kind.designHeight)
        val x = (width - kind.designWidth * scale) / 2
        val y = (height - kind.designHeight * scale) / 2
        return Box(
            x + box.left * scale,
            y + box.top * scale,
            x + box.right * scale,
            y + box.bottom * scale,
        )
    }
}
