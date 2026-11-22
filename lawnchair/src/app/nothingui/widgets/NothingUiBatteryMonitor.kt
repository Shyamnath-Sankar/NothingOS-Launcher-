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

package app.nothingui.widgets

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat

/**
 * Lifecycle-bounded foreground battery receiver.
 *
 * [Intent.ACTION_BATTERY_CHANGED] is sticky and is never delivered to manifest receivers, so the
 * Play launcher activity registers this while it is resumed and unregisters it in `onPause`. It
 * only forwards the real system broadcast to [NothingUiBatteryWidgetProvider]; it is not a
 * service, holds no wake lock and does no work while another app is foreground.
 */
object NothingUiBatteryMonitor {

    private var receiver: BroadcastReceiver? = null

    fun start(context: Context) {
        val appContext = context.applicationContext
        if (receiver != null) {
            NothingUiBatteryWidgetProvider.refreshAll(appContext)
            return
        }
        val newReceiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context?, intent: Intent?) {
                NothingUiBatteryWidgetProvider.refreshAll(appContext, intent)
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_CHANGED)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        }
        ContextCompat.registerReceiver(
            appContext,
            newReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiver = newReceiver
        NothingUiBatteryWidgetProvider.refreshAll(appContext)
    }

    fun stop(context: Context) {
        val current = receiver ?: return
        receiver = null
        runCatching { context.applicationContext.unregisterReceiver(current) }
    }
}
