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

package app.nothingui.launcher

import android.content.Context
import android.content.Intent
import app.lawnchair.LawnchairLauncher
import java.util.UUID

/**
 * One-shot request that brings the launcher home and asks it to open the platform widget picker
 * only after it is resumed. The extras are removed as soon as they are consumed and every request
 * carries its own id, so a recreated activity cannot replay it while a newer request still works.
 */
object WidgetPickerRequest {
    const val EXTRA_OPEN_WIDGET_PICKER = "app.nothingui.extra.OPEN_WIDGET_PICKER"
    const val EXTRA_OPEN_WIDGET_PICKER_ID = "app.nothingui.extra.OPEN_WIDGET_PICKER_ID"
    private const val LEGACY_REQUEST_ID = "legacy-widget-picker-request"

    fun launcherIntent(context: Context): Intent = Intent(context, LawnchairLauncher::class.java)
        .setAction(Intent.ACTION_MAIN)
        .addCategory(Intent.CATEGORY_HOME)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        .putExtra(EXTRA_OPEN_WIDGET_PICKER, true)
        .putExtra(EXTRA_OPEN_WIDGET_PICKER_ID, UUID.randomUUID().toString())

    fun consume(intent: Intent?): String? {
        if (intent == null || !intent.getBooleanExtra(EXTRA_OPEN_WIDGET_PICKER, false)) {
            return null
        }
        val id = intent.getStringExtra(EXTRA_OPEN_WIDGET_PICKER_ID) ?: LEGACY_REQUEST_ID
        intent.removeExtra(EXTRA_OPEN_WIDGET_PICKER)
        intent.removeExtra(EXTRA_OPEN_WIDGET_PICKER_ID)
        return id
    }
}
