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

package app.nothingui.settings

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Starts the platform's own HOME-role consent screen for a user tap.
 *
 * Returns false when the role dialog cannot or should not be shown, so the caller
 * can fall back to the system Home settings screen. The role result is deliberately
 * not interpreted: cancelling the platform dialog leaves the current default home
 * choice unchanged.
 */
object DefaultHomeRoleConsent {

    fun requestRole(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val roleManager = context.getSystemService(RoleManager::class.java) ?: return false
        val action = DefaultHomeRolePolicy.resolve(
            sdkInt = Build.VERSION.SDK_INT,
            roleAvailable = roleManager.isRoleAvailable(RoleManager.ROLE_HOME),
            roleHeld = roleManager.isRoleHeld(RoleManager.ROLE_HOME),
        )
        if (action != DefaultHomeRolePolicy.Action.REQUEST_ROLE) return false
        return try {
            val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME)
            val activity = context as? Activity
            if (activity != null) {
                activity.startActivityForResult(intent, REQUEST_HOME_ROLE)
            } else {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private const val REQUEST_HOME_ROLE = 7401
}
