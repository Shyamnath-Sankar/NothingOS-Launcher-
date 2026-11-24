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
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
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
import app.nothingui.theme.NothingUiPalette
import com.android.launcher3.R
import java.util.Calendar
import java.util.Locale

/**
 * Original NothingUI home date strip.
 *
 * A quiet, borderless date line pinned in the inherited first-row smartspace slot. It is
 * deliberately not a card and not a second clock: the time lives in the square dot clock widget,
 * so the header only carries the date plus one restrained accent dot. The live date still updates
 * on the time tick and timezone/date changes, and drag/drop, widgets, app launch and HOME resume
 * remain the inherited Launcher3 engine.
 */
class NothingUiHomeHeaderView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    private val dateView = TextView(context)
    private val accentView = View(context)
    private val pill = LinearLayout(context)
    private var receiverRegistered = false

    private val timeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            updateDate()
        }
    }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setPadding(dp(14), dp(2), dp(14), dp(2))

        pill.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                dp(PILL_H_PADDING_DP),
                dp(PILL_V_PADDING_DP),
                dp(PILL_H_PADDING_DP),
                dp(PILL_V_PADDING_DP),
            )
        }

        dateView.apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, DATE_TEXT_SP)
            letterSpacing = 0.24f
            typeface = dotoRegular()
            includeFontPadding = false
            maxLines = 1
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        pill.addView(
            dateView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )

        accentView.apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(NothingUiPalette.AccentRed.toArgb())
            }
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        pill.addView(
            accentView,
            LinearLayout.LayoutParams(dp(ACCENT_DOT_DP), dp(ACCENT_DOT_DP)).apply {
                marginStart = dp(8)
            },
        )

        addView(
            pill,
            LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_VERTICAL or Gravity.START,
            ),
        )

        applyTheme()
        updateDate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        applyTheme()
        registerTimeReceiver()
        updateDate()
    }

    private fun applyTheme() {
        pill.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(PILL_CORNER_DP).toFloat()
            setColor(NothingUiHomeChrome.surfaceColor(context))
        }
        dateView.setTextColor(NothingUiHomeChrome.textColor(context))
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

    private fun updateDate() {
        val now = Calendar.getInstance()
        val date = NothingUiHomeClock.formatDate(now, currentLocale())
        dateView.text = date
        dateView.contentDescription = date
    }

    private fun currentLocale(): Locale {
        val locales = context.resources.configuration.locales
        return if (locales.isEmpty) Locale.getDefault() else locales[0]
    }

    private fun dotoRegular(): Typeface {
        return ResourcesCompat.getFont(context, R.font.doto_regular) ?: Typeface.SANS_SERIF
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private companion object {
        const val DATE_TEXT_SP = 11f
        const val ACCENT_DOT_DP = 4
        const val PILL_H_PADDING_DP = 10
        const val PILL_V_PADDING_DP = 3
        const val PILL_CORNER_DP = 12
    }
}
