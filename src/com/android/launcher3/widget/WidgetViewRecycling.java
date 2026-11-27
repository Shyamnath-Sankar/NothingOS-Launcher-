/*
 * Copyright (C) 2026 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.android.launcher3.widget;

import androidx.annotation.Nullable;

/** Pure helpers for keeping a widget item usable when its view is recreated during attach. */
public final class WidgetViewRecycling {

    private WidgetViewRecycling() {}

    /**
     * Returns the tag the recycled view must carry so it can be added back to the workspace.
     *
     * <p>{@link LauncherWidgetHolder#attachViewToHostAndGetAttachedView} can replace a placeholder
     * with a fresh pending view when the holder stops listening between inflation and binding. The
     * fresh instance has no tag, so {@code WorkspaceLayoutManager} rejects it with "Attempted to
     * add null item to workspace" and {@link PendingAppWidgetHostView#reInflate} later skips it.
     * Keep the original item when the recycled instance has none, and never clobber a tag that
     * the recycling flow already set.
     */
    @Nullable
    public static Object resolveItemTag(
            @Nullable Object originalTag, @Nullable Object recycledTag) {
        return recycledTag == null ? originalTag : recycledTag;
    }
}
