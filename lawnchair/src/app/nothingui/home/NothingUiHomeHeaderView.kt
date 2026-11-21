/*
 * Copyright 2026 the DotWel Launcher project contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package app.nothingui.home

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.format.DateFormat
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.ContextCompat
import androidx.core.content.res.ResourcesCompat
import androidx.core.graphics.ColorUtils
import app.nothingui.theme.NothingUiPalette
import com.android.launcher3.R
import com.android.launcher3.util.Themes
import java.util.Calendar
import java.util.Locale

/**
 * Original NothingUI home header.
 *
 * Replaces the inherited onboarding smartspace card on the Play channel only. It renders a
 * neutral modular card, a live Doto clock and date, a restrained red accent and a small
 * monochrome dot motif. It never stands in for the workspace itself: it is the pinned first-row
 * item inside the inherited Launcher3 workspace, so drag/drop, widgets, app launch and HOME
 * resume continue to use the inherited engine.
 */
class NothingUiHomeHeaderView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    private val clockView = TextView(context)
    private val dateView = TextView(context)
    private val accentView = View(context)
    private val dotsView = DotStripView(context)
    private var receiverRegistered = false

    private val timeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            updateTime()
        }
    }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setPadding(dp(12), dp(8), dp(12), dp(8))

        val card = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(28).toFloat()
                setColor(cardColor())
                setStroke(dp(1), outlineColor())
            }
            setPadding(dp(20), dp(14), dp(20), dp(14))
        }

        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val topRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        dateView.apply {
            setTextColor(textColor())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            letterSpacing = 0.28f
            typeface = dotoRegular()
            includeFontPadding = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        topRow.addView(
            dateView,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )

        accentView.apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(NothingUiPalette.AccentRed.toArgb())
            }
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        topRow.addView(
            accentView,
            LinearLayout.LayoutParams(dp(6), dp(6)).apply { marginStart = dp(8) },
        )

        content.addView(
            topRow,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )

        clockView.apply {
            setTextColor(textColor())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 40f)
            letterSpacing = -0.02f
            typeface = dotoBold()
            includeFontPadding = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        content.addView(
            clockView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(2) },
        )

        dotsView.dotColor = textColor()
        content.addView(
            dotsView,
            LinearLayout.LayoutParams(dp(56), dp(8)).apply { topMargin = dp(6) },
        )

        card.addView(
            content,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        addView(
            card,
            LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )

        updateTime()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        registerTimeReceiver()
        updateTime()
    }

    override fun onDetachedFromWindow() {
        if (receiverRegistered) {
            context.unregisterReceiver(timeReceiver)
            receiverRegistered = false
        }
        super.onDetachedFromWindow()
    }

    private fun registerTimeReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_TICK)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_DATE_CHANGED)
        }
        ContextCompat.registerReceiver(
            context,
            timeReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiverRegistered = true
    }

    private fun updateTime() {
        val now = Calendar.getInstance()
        val is24Hour = DateFormat.is24HourFormat(context)
        val locale = currentLocale()
        val clock = NothingUiHomeClock.formatClock(now, is24Hour, locale)
        val date = NothingUiHomeClock.formatDate(now, locale)
        clockView.text = clock
        clockView.contentDescription = clock
        dateView.text = date
        dateView.contentDescription = date
    }

    private fun currentLocale(): Locale {
        val locales = context.resources.configuration.locales
        return if (locales.isEmpty) Locale.getDefault() else locales[0]
    }

    private fun cardColor(): Int {
        val color = if (isWorkspaceDarkText()) {
            NothingUiPalette.Paper.toArgb()
        } else {
            NothingUiPalette.Gray900.toArgb()
        }
        return ColorUtils.setAlphaComponent(color, CARD_ALPHA)
    }

    private fun textColor(): Int {
        return if (isWorkspaceDarkText()) {
            NothingUiPalette.Ink.toArgb()
        } else {
            NothingUiPalette.Paper.toArgb()
        }
    }

    private fun outlineColor(): Int {
        return ColorUtils.setAlphaComponent(textColor(), OUTLINE_ALPHA)
    }

    private fun isWorkspaceDarkText(): Boolean {
        return runCatching {
            Themes.getAttrBoolean(context, R.attr.isWorkspaceDarkText)
        }.getOrDefault(false)
    }

    private fun dotoRegular(): Typeface {
        return ResourcesCompat.getFont(context, R.font.doto_regular) ?: Typeface.SANS_SERIF
    }

    private fun dotoBold(): Typeface {
        return ResourcesCompat.getFont(context, R.font.doto_bold) ?: Typeface.SANS_SERIF
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private class DotStripView(context: Context) : View(context) {
        var dotColor: Int = 0
            set(value) {
                field = value
                invalidate()
            }

        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (width <= 0 || height <= 0) return
            val radius = height / 2f * 0.55f
            val gap = radius * 2.4f
            var x = radius
            var index = 0
            while (x + radius <= width && index < 6) {
                val alpha = if (index == 0) 255 else 90
                paint.color = ColorUtils.setAlphaComponent(dotColor, alpha)
                canvas.drawCircle(x, height / 2f, radius, paint)
                x += gap
                index++
            }
        }
    }

    private companion object {
        const val CARD_ALPHA = 242
        const val OUTLINE_ALPHA = 46
    }
}
