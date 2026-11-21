/*
 * Copyright 2026, Lawnchair
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

package app.lawnchair.search.algorithms

import com.android.launcher3.model.data.ItemInfoWithIcon

/**
 * True when an app's runtime status marks it as belonging to a locked profile.
 *
 * Private-space and quiet work profiles set [ItemInfoWithIcon.FLAG_DISABLED_QUIET_USER] on their
 * apps. Keep this predicate pure so it can be covered by a plain JVM unit test.
 */
internal fun isLockedProfile(runtimeStatusFlags: Int): Boolean =
    runtimeStatusFlags and ItemInfoWithIcon.FLAG_DISABLED_QUIET_USER != 0
