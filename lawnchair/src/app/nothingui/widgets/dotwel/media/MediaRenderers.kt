package app.nothingui.widgets.dotwel.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import app.nothingui.widgets.dotwel.BatteryState
import app.nothingui.widgets.dotwel.WidgetStyle
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
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
 * Source-derived Canvas renderers for the twelve media/notification presets.
 * Each one keeps the author canvas proportions and the module positions listed
 * in the sanitized source transcriptions; platform sans-serif text and original
 * vector transport icons replace the source's bundled font/icon payloads.
 */
object MediaRenderers {
    private const val DEFAULT_CORNER = 28f
    private val clockFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

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
        val palette = if (kind == MediaWidgetKind.M3_EXPANDED || kind == MediaWidgetKind.M3_OUTPUT) {
            // These two source cards deliberately darken cover art in every style.
            MediaDraw.palette(WidgetStyle.BLACK)
        } else {
            MediaDraw.palette(style)
        }
        val scale = min(
            safeWidth / kind.designWidth,
            safeHeight / kind.designHeight,
        ).coerceAtLeast(0.01f)
        val offsetX = (safeWidth - kind.designWidth * scale) / 2f
        val offsetY = (safeHeight - kind.designHeight * scale) / 2f
        canvas.save()
        canvas.translate(offsetX, offsetY)
        canvas.scale(scale, scale)
        when (kind) {
            MediaWidgetKind.M3_EXPANDED -> drawM3Expanded(canvas, palette, snapshot)

            MediaWidgetKind.M3_OUTPUT -> drawM3Output(canvas, palette, snapshot)

            MediaWidgetKind.MINI -> drawMini(canvas, palette, snapshot)

            MediaWidgetKind.MINIMAL -> drawMinimal(canvas, palette, snapshot, variant = 1)

            MediaWidgetKind.MINIMAL_2 -> drawMinimal(canvas, palette, snapshot, variant = 2)

            MediaWidgetKind.MINIMAL_3 -> drawMinimal(canvas, palette, snapshot, variant = 3)

            MediaWidgetKind.NOTHING_MASTER ->
                drawNothingMaster(canvas, palette, snapshot, BatteryState.level(context))

            MediaWidgetKind.NOTHING_PLAYER -> drawNothingPlayer(canvas, palette, snapshot)

            MediaWidgetKind.NOTHING_PLAYER_2 -> drawNothingPlayer2(canvas, palette, snapshot)

            MediaWidgetKind.NOTHING_PLAYER_3 -> drawNothingPlayer3(canvas, palette, snapshot)

            MediaWidgetKind.UNIVERSAL -> drawUniversal(canvas, palette, snapshot)

            MediaWidgetKind.NOTIFICATION -> drawNotification(canvas, palette, snapshot)
        }
        canvas.restore()
        return bitmap
    }

    private fun card(canvas: Canvas, palette: MediaPalette, width: Float, height: Float, radius: Float = DEFAULT_CORNER) {
        MediaDraw.background(
            canvas,
            RectF(0f, 0f, width, height),
            radius,
            palette.background,
        )
    }

    private fun drawControls(
        canvas: Canvas,
        palette: MediaPalette,
        snapshot: MediaSnapshot,
        centerX: Float,
        centerY: Float,
        playSize: Float,
        skipSize: Float,
        gap: Float,
    ) {
        MediaDraw.drawSkip(
            canvas,
            centerX - gap,
            centerY,
            skipSize,
            previous = true,
            palette.ink,
            snapshot.canSkipPrevious,
        )
        MediaDraw.drawPlayPause(
            canvas,
            centerX,
            centerY,
            playSize,
            snapshot.isPlaying,
            if (snapshot.canPlayPause) palette.primary else palette.muted,
        )
        MediaDraw.drawSkip(
            canvas,
            centerX + gap,
            centerY,
            skipSize,
            previous = false,
            palette.ink,
            snapshot.canSkipNext,
        )
    }

    private fun fraction(snapshot: MediaSnapshot): Float {
        if (snapshot.durationMillis <= 0L) return 0f
        return (snapshot.positionMillis.toFloat() / snapshot.durationMillis.toFloat())
            .coerceIn(0f, 1f)
    }

    private fun drawM3Expanded(canvas: Canvas, palette: MediaPalette, snapshot: MediaSnapshot) {
        val w = MediaWidgetKind.M3_EXPANDED.designWidth
        val h = MediaWidgetKind.M3_EXPANDED.designHeight
        MediaDraw.cover(canvas, snapshot.albumArt, RectF(0f, 0f, w, h), DEFAULT_CORNER, palette.accent)
        canvas.drawRect(
            0f,
            0f,
            w,
            h,
            MediaDraw.fill(0xCC121316.toInt()),
        )
        val title = MediaDraw.text(palette.ink, 42f, bold = true)
        val artist = MediaDraw.text(palette.muted, 32f)
        val small = MediaDraw.text(palette.muted, 24f)
        MediaDraw.drawText(canvas, title, snapshot.title ?: "Nothing playing", 96f, 248f, w - 320f)
        MediaDraw.drawText(canvas, artist, snapshot.artist, 96f, 300f, w - 320f)
        MediaDraw.drawText(canvas, small, snapshot.appLabel, 36f, 80f, 420f)
        drawOutputBadge(canvas, palette, snapshot, w - 36f, 36f)
        drawControls(canvas, palette, snapshot, w / 2f, h - 66f, 54f, 40f, 130f)
        MediaDraw.drawProgress(
            canvas,
            RectF(96f, h - 140f, w - 96f, h - 134f),
            fraction(snapshot),
            palette.ink,
            palette.accent,
        )
        MediaDraw.drawText(canvas, small, MediaDraw.timeText(snapshot.positionMillis), 96f, h - 42f, 200f)
        MediaDraw.drawText(
            canvas,
            small,
            MediaDraw.timeText(snapshot.durationMillis),
            w - 96f,
            h - 42f,
            200f,
            Paint.Align.RIGHT,
        )
    }

    private fun drawM3Output(canvas: Canvas, palette: MediaPalette, snapshot: MediaSnapshot) {
        val w = MediaWidgetKind.M3_OUTPUT.designWidth
        val h = MediaWidgetKind.M3_OUTPUT.designHeight
        MediaDraw.cover(canvas, snapshot.albumArt, RectF(0f, 0f, w, h), DEFAULT_CORNER, palette.accent)
        canvas.drawRect(0f, 0f, w, h, MediaDraw.fill(0xCC121316.toInt()))
        val title = MediaDraw.text(palette.ink, 42f, bold = true)
        val artist = MediaDraw.text(palette.muted, 32f)
        val small = MediaDraw.text(palette.muted, 22f)
        MediaDraw.drawText(canvas, title, snapshot.title ?: "Nothing playing", 96f, 256f, w - 320f)
        MediaDraw.drawText(canvas, artist, snapshot.artist, 96f, 308f, w - 320f)
        MediaDraw.drawDevice(canvas, w - 74f, 52f, 34f, palette.ink)
        MediaDraw.drawText(
            canvas,
            small,
            snapshot.appLabel ?: "Output",
            w - 104f,
            50f,
            300f,
            Paint.Align.RIGHT,
        )
        drawControls(canvas, palette, snapshot, w / 2f, h - 66f, 54f, 40f, 130f)
        MediaDraw.drawProgress(
            canvas,
            RectF(96f, h - 140f, w - 96f, h - 134f),
            fraction(snapshot),
            palette.primary,
            palette.accent,
        )
        MediaDraw.drawText(canvas, small, MediaDraw.timeText(snapshot.positionMillis), 96f, h - 42f, 200f)
        MediaDraw.drawText(
            canvas,
            small,
            MediaDraw.timeText(snapshot.durationMillis),
            w - 96f,
            h - 42f,
            200f,
            Paint.Align.RIGHT,
        )
    }

    private fun drawMini(canvas: Canvas, palette: MediaPalette, snapshot: MediaSnapshot) {
        val w = MediaWidgetKind.MINI.designWidth
        val h = MediaWidgetKind.MINI.designHeight
        card(canvas, palette, w, h, radius = 40f)
        MediaDraw.cover(
            canvas,
            snapshot.albumArt,
            RectF(24f, 24f, 300f, 300f),
            28f,
            palette.accent,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 22f),
            snapshot.appLabel,
            w - 24f,
            56f,
            220f,
            Paint.Align.RIGHT,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.ink, 40f, bold = true),
            snapshot.title,
            24f,
            382f,
            w - 48f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 28f),
            snapshot.artist,
            24f,
            424f,
            w - 48f,
        )
        MediaDraw.drawProgress(
            canvas,
            RectF(24f, 456f, w - 24f, 462f),
            fraction(snapshot),
            palette.primary,
            palette.accent,
        )
        MediaDraw.drawSkip(canvas, 40f, h - 40f, 34f, true, palette.ink, snapshot.canSkipPrevious)
        MediaDraw.drawPlayPause(canvas, 96f, h - 40f, 52f, snapshot.isPlaying, if (snapshot.canPlayPause) palette.primary else palette.muted)
        MediaDraw.drawSkip(canvas, 152f, h - 40f, 34f, false, palette.ink, snapshot.canSkipNext)
    }

    private fun drawMinimal(
        canvas: Canvas,
        palette: MediaPalette,
        snapshot: MediaSnapshot,
        variant: Int,
    ) {
        val w = MediaWidgetKind.MINIMAL.designWidth
        val h = MediaWidgetKind.MINIMAL.designHeight
        card(canvas, palette, w, h, radius = 32f)
        if (variant == 2) {
            canvas.drawRect(0f, 0f, 10f, h, MediaDraw.fill(palette.primary))
        } else if (variant == 3) {
            canvas.drawRect(0f, h - 8f, w, h, MediaDraw.fill(palette.accent))
        }
        val artLeft = if (variant == 2) 36f else 28f
        val artRight = artLeft + 112f
        MediaDraw.cover(
            canvas,
            snapshot.albumArt,
            RectF(artLeft, 42f, artRight, 154f),
            if (variant == 2) 20f else 56f,
            palette.accent,
        )
        val textX = artRight + 24f
        val buttonStart = w - 260f
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.ink, 34f, bold = true),
            snapshot.title,
            textX,
            98f,
            buttonStart - textX - 12f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 25f),
            snapshot.artist,
            textX,
            136f,
            buttonStart - textX - 12f,
        )
        if (variant == 3) {
            MediaDraw.drawProgress(
                canvas,
                RectF(textX, 156f, buttonStart - 24f, 164f),
                fraction(snapshot),
                palette.primary,
                palette.accent,
            )
            MediaDraw.drawText(
                canvas,
                MediaDraw.text(palette.muted, 18f),
                MediaDraw.timeText(snapshot.positionMillis),
                textX,
                188f,
                120f,
            )
        }
        drawControls(canvas, palette, snapshot, buttonStart + 116f, h / 2f, 48f, 34f, 78f)
    }

    private fun drawNothingMaster(
        canvas: Canvas,
        palette: MediaPalette,
        snapshot: MediaSnapshot,
        batteryLevel: Int,
    ) {
        val w = MediaWidgetKind.NOTHING_MASTER.designWidth
        val h = MediaWidgetKind.NOTHING_MASTER.designHeight
        card(canvas, palette, w, h, radius = 48f)
        val side = min(w, h)
        val big = MediaDraw.text(palette.primary, side / 6f, bold = true)
        MediaDraw.drawText(canvas, big, "$batteryLevel", w / 2f, side * 0.18f, w - 40f, Paint.Align.CENTER)
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, side / 24f),
            "BATTERY",
            w / 2f,
            side * 0.22f,
            w - 40f,
            Paint.Align.CENTER,
        )
        val day = SimpleDateFormat("EEE", Locale.getDefault()).format(Date())
        val month = SimpleDateFormat("MMM d", Locale.getDefault()).format(Date())
        MediaDraw.drawText(canvas, MediaDraw.text(palette.muted, side / 18f), day, 56f, h * 0.34f, 240f)
        MediaDraw.drawText(canvas, MediaDraw.text(palette.ink, side / 9f, bold = true), month, 56f, h * 0.40f, 360f)
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, side / 22f),
            "WEATHER OFF",
            w - 56f,
            h * 0.39f,
            260f,
            Paint.Align.RIGHT,
        )
        val time = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.ink, side / 4.2f, bold = true),
            time,
            56f,
            h * 0.62f,
            w - 112f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, side / 20f),
            "NOW PLAYING",
            56f,
            h * 0.69f,
            400f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.ink, side / 15f, bold = true),
            snapshot.title ?: "No active media",
            56f,
            h * 0.75f,
            w - 112f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, side / 22f),
            snapshot.artist ?: if (!snapshot.accessGranted) "Tap to enable media access" else "Play music in your player",
            56f,
            h * 0.79f,
            w - 112f,
        )
        MediaDraw.drawProgress(
            canvas,
            RectF(56f, h * 0.84f, w - 56f, h * 0.84f + 8f),
            fraction(snapshot),
            palette.primary,
            palette.accent,
        )
        drawControls(canvas, palette, snapshot, w / 2f, h * 0.92f, 58f, 40f, 140f)
    }

    private fun drawNothingPlayer(canvas: Canvas, palette: MediaPalette, snapshot: MediaSnapshot) {
        val w = MediaWidgetKind.NOTHING_PLAYER.designWidth
        val h = MediaWidgetKind.NOTHING_PLAYER.designHeight
        card(canvas, palette, w, h, radius = 40f)
        val cardRect = RectF(w * 0.12f, h * 0.14f, w * 0.88f, h * 0.86f)
        MediaDraw.background(canvas, cardRect, 24f, palette.accent)
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 22f),
            snapshot.appLabel,
            cardRect.left + 28f,
            cardRect.top + 42f,
            380f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.ink, 36f, bold = true),
            snapshot.title,
            cardRect.left + 28f,
            cardRect.top + 92f,
            cardRect.width() - 56f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 26f),
            snapshot.artist,
            cardRect.left + 28f,
            cardRect.top + 128f,
            cardRect.width() - 56f,
        )
        drawControls(canvas, palette, snapshot, w / 2f, h * 0.58f, 76f, 46f, 160f)
        MediaDraw.drawProgress(
            canvas,
            RectF(cardRect.left + 28f, h * 0.72f, cardRect.right - 28f, h * 0.72f + 8f),
            fraction(snapshot),
            palette.primary,
            palette.accent,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 22f),
            MediaDraw.timeText(snapshot.positionMillis),
            cardRect.left + 28f,
            h * 0.76f,
            160f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 22f),
            MediaDraw.timeText(snapshot.durationMillis),
            cardRect.right - 28f,
            h * 0.76f,
            160f,
            Paint.Align.RIGHT,
        )
    }

    private fun drawNothingPlayer2(canvas: Canvas, palette: MediaPalette, snapshot: MediaSnapshot) {
        val w = MediaWidgetKind.NOTHING_PLAYER_2.designWidth
        val h = MediaWidgetKind.NOTHING_PLAYER_2.designHeight
        card(canvas, palette, w, h, radius = h / 4f)
        MediaDraw.background(
            canvas,
            RectF(18f, 18f, w * 0.72f, h - 18f),
            h / 4f,
            palette.accent,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.primary, 18f),
            snapshot.packageName ?: "media",
            w * 0.72f - 36f,
            56f,
            w * 0.72f - 72f,
            Paint.Align.RIGHT,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.ink, 30f, bold = true),
            snapshot.title,
            42f,
            118f,
            w * 0.72f - 84f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 22f),
            snapshot.artist,
            42f,
            154f,
            w * 0.72f - 84f,
        )
        val centerX = w * 0.86f
        canvas.drawCircle(centerX, h / 2f, h / 2.5f, MediaDraw.fill(palette.accent))
        MediaDraw.drawPlayPause(canvas, centerX, h / 2f, 42f, snapshot.isPlaying, if (snapshot.canPlayPause) palette.primary else palette.muted)
    }

    private fun drawNothingPlayer3(canvas: Canvas, palette: MediaPalette, snapshot: MediaSnapshot) {
        val w = MediaWidgetKind.NOTHING_PLAYER_3.designWidth
        val h = MediaWidgetKind.NOTHING_PLAYER_3.designHeight
        card(canvas, palette, w, h, radius = 56f)
        val side = w
        val panel = RectF(side * 0.10f, side * 0.18f, side * 0.90f, h - side * 0.18f)
        MediaDraw.background(canvas, panel, side / 5f, palette.accent)
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.ink, side / 16f, bold = true),
            snapshot.title,
            w - side / 12f,
            side / 8f,
            side / 1.25f,
            Paint.Align.RIGHT,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, side / 24f),
            snapshot.artist,
            w - side / 12f,
            side / 8f + side / 18f,
            side / 1.4f,
            Paint.Align.RIGHT,
        )
        val barCenter = w * 0.30f
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(if (snapshot.canAdjustVolume) palette.muted else palette.accent, side / 18f),
            "+",
            barCenter - side / 6f,
            h * 0.42f,
            40f,
            Paint.Align.CENTER,
        )
        MediaDraw.drawProgress(
            canvas,
            RectF(barCenter - side / 10f, h * 0.41f, barCenter + side / 10f, h * 0.41f + 6f),
            snapshot.volumeFraction ?: 0f,
            palette.ink,
            palette.accent,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(if (snapshot.canAdjustVolume) palette.muted else palette.accent, side / 18f),
            "-",
            barCenter + side / 6f,
            h * 0.42f,
            40f,
            Paint.Align.CENTER,
        )
        MediaDraw.drawProgress(
            canvas,
            RectF(w * 0.12f, h * 0.56f, w * 0.88f, h * 0.56f + 10f),
            fraction(snapshot),
            palette.primary,
            palette.accent,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, side / 22f),
            MediaDraw.timeText(snapshot.positionMillis),
            w * 0.12f,
            h * 0.60f,
            120f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, side / 22f),
            MediaDraw.timeText(snapshot.durationMillis),
            w * 0.88f,
            h * 0.60f,
            120f,
            Paint.Align.RIGHT,
        )
        drawControls(canvas, palette, snapshot, w / 2f, h * 0.76f, 74f, 46f, 132f)
    }

    private fun drawUniversal(canvas: Canvas, palette: MediaPalette, snapshot: MediaSnapshot) {
        val w = MediaWidgetKind.UNIVERSAL.designWidth
        val h = MediaWidgetKind.UNIVERSAL.designHeight
        card(canvas, palette, w, h, radius = 36f)
        MediaDraw.cover(
            canvas,
            snapshot.albumArt,
            RectF(32f, h / 2f - 150f, 332f, h / 2f + 150f),
            24f,
            palette.accent,
        )
        val textX = 372f
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 22f),
            snapshot.artist?.uppercase(),
            textX,
            150f,
            w - textX - 80f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.ink, 38f, bold = true),
            snapshot.title,
            textX,
            210f,
            w - textX - 80f,
        )
        MediaDraw.drawProgress(
            canvas,
            RectF(textX, 246f, w - 80f, 254f),
            fraction(snapshot),
            palette.primary,
            palette.accent,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 20f),
            MediaDraw.timeText(snapshot.positionMillis) + " / " +
                MediaDraw.timeText(snapshot.durationMillis),
            textX,
            282f,
            300f,
        )
        drawControls(canvas, palette, snapshot, w - 190f, 360f, 58f, 40f, 86f)
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 20f),
            snapshot.appLabel,
            w - 50f,
            h - 50f,
            320f,
            Paint.Align.RIGHT,
        )
    }

    private fun drawNotification(canvas: Canvas, palette: MediaPalette, snapshot: MediaSnapshot) {
        val w = MediaWidgetKind.NOTIFICATION.designWidth
        val h = MediaWidgetKind.NOTIFICATION.designHeight
        card(canvas, palette, w, h, radius = 36f)
        val notification = snapshot.notification
        if (snapshot.title == null && notification == null) {
            MediaDraw.drawText(
                canvas,
                MediaDraw.text(palette.muted, 36f),
                if (snapshot.accessGranted) "NO NOTIFICATIONS" else "NOTIFICATION ACCESS OFF",
                w / 2f,
                h / 2f,
                w - 80f,
                Paint.Align.CENTER,
            )
            MediaDraw.drawText(
                canvas,
                MediaDraw.text(palette.muted, 20f),
                if (snapshot.accessGranted) {
                    "Waiting for a notification"
                } else {
                    "Tap to open the explanation"
                },
                w / 2f,
                h / 2f + 42f,
                w - 120f,
                Paint.Align.CENTER,
            )
            return
        }
        val title = notification?.title ?: snapshot.title
        val text = notification?.text ?: snapshot.artist
        val app = notification?.appLabel ?: snapshot.appLabel
        val posted = notification?.postedAtMillis ?: snapshot.capturedAtMillis
        canvas.drawCircle(74f, h / 2f, 34f, MediaDraw.fill(palette.primary))
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.onPrimary, 26f, bold = true),
            app?.take(1)?.uppercase() ?: "N",
            74f,
            h / 2f + 10f,
            60f,
            Paint.Align.CENTER,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.ink, 28f, bold = true),
            title,
            132f,
            86f,
            w - 360f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 24f),
            text,
            132f,
            124f,
            w - 360f,
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 20f),
            "${app ?: ""} \u00B7 ${clockFormat.format(Date(posted))}",
            132f,
            166f,
            w - 420f,
        )
        MediaDraw.background(
            canvas,
            RectF(w - 210f, h - 78f, w - 34f, h - 28f),
            14f,
            0xFF9B1919.toInt(),
        )
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.onPrimary, 22f, bold = true),
            "CLEAR",
            w - 122f,
            h - 44f,
            140f,
            Paint.Align.CENTER,
        )
        if (!snapshot.accessGranted) {
            MediaDraw.drawText(
                canvas,
                MediaDraw.text(palette.muted, 16f),
                "Access off",
                w - 34f,
                46f,
                160f,
                Paint.Align.RIGHT,
            )
        }
    }

    private fun drawOutputBadge(
        canvas: Canvas,
        palette: MediaPalette,
        snapshot: MediaSnapshot,
        right: Float,
        top: Float,
    ) {
        MediaDraw.drawDevice(canvas, right - 34f, top + 34f, 30f, palette.ink)
        MediaDraw.drawText(
            canvas,
            MediaDraw.text(palette.muted, 22f),
            snapshot.appLabel ?: "Media",
            right - 60f,
            top + 28f,
            300f,
            Paint.Align.RIGHT,
        )
    }
}
