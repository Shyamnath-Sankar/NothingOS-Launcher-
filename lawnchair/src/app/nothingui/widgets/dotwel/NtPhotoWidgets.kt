package app.nothingui.widgets.dotwel

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Bundle
import android.widget.RemoteViews
import android.widget.Toast
import com.android.launcher3.R
import java.io.File

/** NtPhoto center-crop, 4% inset and oval/30% corner mask, actual author source. */
object NtPhotoRenderer {
    fun file(context: Context, id: Int) = File(context.noBackupFilesDir, "ntphoto_$id.jpg")
    fun render(context: Context, id: Int, width: Int, height: Int, circle: Boolean, style: WidgetStyle): Bitmap {
        val side = minOf(width, height).coerceAtLeast(1)
        val w = if (circle) side else width.coerceAtLeast(1)
        val h = if (circle) side else height.coerceAtLeast(1)
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val inset = minOf(w, h) * .04f
        val corner = minOf(w, h) * .30f
        val outer = RectF(0f, 0f, w.toFloat(), h.toFloat())
        val inner = RectF(inset, inset, w - inset, h - inset)
        p.color = UpstreamNtDraw.background(context, style)
        if (circle) canvas.drawOval(outer, p) else canvas.drawRoundRect(outer, corner, corner, p)
        val source = BitmapFactory.decodeFile(file(context, id).path)
        if (source == null) {
            p.color = UpstreamNtDraw.muted(context, style)
            p.strokeWidth = maxOf(2f, inset * .5f)
            p.strokeCap = Paint.Cap.ROUND
            val arm = minOf(w, h) * .12f
            canvas.drawLine(w / 2f - arm, h / 2f, w / 2f + arm, h / 2f, p)
            canvas.drawLine(w / 2f, h / 2f - arm, w / 2f, h / 2f + arm, p)
        } else {
            val saved = canvas.save()
            val path = Path().apply {
                if (circle) {
                    addOval(inner, Path.Direction.CW)
                } else {
                    addRoundRect(inner, corner - inset, corner - inset, Path.Direction.CW)
                }
            }
            canvas.clipPath(path)
            val scale = maxOf(inner.width() / source.width, inner.height() / source.height)
            val sw = source.width * scale
            val sh = source.height * scale
            val target = RectF(inner.centerX() - sw / 2, inner.centerY() - sh / 2, inner.centerX() + sw / 2, inner.centerY() + sh / 2)
            canvas.drawBitmap(source, null, target, p)
            canvas.restoreToCount(saved)
            source.recycle()
        }
        return out
    }
}

abstract class BaseNtPhotoProvider : BaseWidgetProvider() {
    protected abstract val circle: Boolean
    override val layoutRes = R.layout.widget_weather_temp
    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews = buildBitmapViews(
        context,
        appWidgetId,
        R.id.weather_temp_bitmap,
        R.id.weather_temp_fallback,
        render = { w, h -> NtPhotoRenderer.render(context, appWidgetId, w, h, circle, WidgetPrefs.style(context)) },
    ) { views, _ ->
        val intent = Intent(context, NtPhotoConfigActivity::class.java).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
    }
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { NtPhotoRenderer.file(context, it).delete() }
        super.onDeleted(context, appWidgetIds)
    }
}
class NtPhotoCircleProvider : BaseNtPhotoProvider() {
    override val circle = true
}
class NtPhotoRectProvider : BaseNtPhotoProvider() {
    override val circle = false
}

/** Per-widget system picker. No broad photo access, remote upload, or retained URI. */
class NtPhotoConfigActivity : Activity() {
    private var id = AppWidgetManager.INVALID_APPWIDGET_ID
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        setResult(RESULT_CANCELED)
        if (!owned()) {
            finish()
            return
        }
        if (savedInstanceState == null) {
            startActivityForResult(
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                },
                1,
            )
        }
    }
    private fun owned(): Boolean {
        val name = AppWidgetManager.getInstance(this).getAppWidgetInfo(id)?.provider?.className
        return name == NtPhotoCircleProvider::class.java.name || name == NtPhotoRectProvider::class.java.name
    }

    @Deprecated("Platform Activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data
        if (requestCode != 1 || resultCode != RESULT_OK || uri == null || !owned()) {
            finish()
            return
        }
        Thread {
            val success = runCatching {
                val bitmap = if (android.os.Build.VERSION.SDK_INT >= 28) {
                    ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri)) { decoder, info, _ ->
                        val ratio = minOf(1f, 1200f / maxOf(info.size.width, info.size.height))
                        decoder.setTargetSize(maxOf(1, (info.size.width * ratio).toInt()), maxOf(1, (info.size.height * ratio).toInt()))
                        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    }
                } else {
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, bounds) }
                    check(bounds.outWidth > 0 && bounds.outHeight > 0)
                    var sample = 1
                    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 2400) sample *= 2
                    val options = BitmapFactory.Options().apply { inSampleSize = sample }
                    contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, options) }
                        ?: error("Image decode failed")
                }
                val pending = File(noBackupFilesDir, "ntphoto_$id.tmp")
                try {
                    pending.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
                    check(owned())
                    check(pending.renameTo(NtPhotoRenderer.file(this, id)))
                } finally {
                    bitmap.recycle()
                    pending.delete()
                }
            }.isSuccess
            runOnUiThread {
                if (success && owned()) {
                    WidgetUpdater.updateAll(this)
                    setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
                } else {
                    Toast.makeText(this, "Could not save this image", Toast.LENGTH_SHORT).show()
                }
                finish()
            }
        }.start()
    }
}
