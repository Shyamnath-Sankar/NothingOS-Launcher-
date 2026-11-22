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

package app.lawnchair.ui.preferences.destinations

import android.app.WallpaperManager
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.core.content.getSystemService
import app.lawnchair.ui.preferences.components.layout.PreferenceGroup
import app.lawnchair.ui.preferences.components.layout.PreferenceLayout
import app.nothingui.theme.NothingUiPalette
import app.nothingui.theme.NothingUiSpacing
import app.nothingui.wallpaper.AmoledWallpaper
import app.nothingui.wallpaper.AmoledWallpaperApplier
import app.nothingui.wallpaper.AmoledWallpaperApplyResult
import app.nothingui.wallpaper.AmoledWallpaperCatalog
import com.android.launcher3.R
import kotlinx.coroutines.launch

@Composable
fun AmoledWallpaperPreferences(
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    val selected = selectedId?.let { AmoledWallpaperCatalog.byId(it) }
    var applying by remember { mutableStateOf(false) }
    var messageRes by remember { mutableStateOf<Int?>(null) }
    val manager = remember { context.getSystemService<WallpaperManager>() }

    PreferenceLayout(
        label = stringResource(R.string.dotwel_amoled_wallpapers_label),
        modifier = modifier,
    ) {
        PreferenceGroup {
            Text(
                text = stringResource(R.string.dotwel_amoled_wallpapers_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = NothingUiSpacing.Lg,
                    vertical = NothingUiSpacing.Sm,
                ),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = NothingUiSpacing.Lg),
                horizontalArrangement = Arrangement.spacedBy(NothingUiSpacing.Md),
            ) {
                AmoledWallpaperCatalog.entries.forEach { wallpaper ->
                    WallpaperTile(
                        wallpaper = wallpaper,
                        selected = selectedId == wallpaper.id,
                        enabled = !applying,
                        onSelect = {
                            if (!applying) {
                                selectedId = wallpaper.id
                                messageRes = null
                            }
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            Text(
                text = stringResource(R.string.dotwel_wallpaper_preview_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = NothingUiSpacing.Lg,
                    vertical = NothingUiSpacing.Md,
                ),
            )
        }

        selected?.let { wallpaper ->
            PreferenceGroup(heading = stringResource(wallpaper.titleRes)) {
                AmoledWallpaperPreview(wallpaper)
                Text(
                    text = stringResource(wallpaper.creditRes),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(horizontal = NothingUiSpacing.Lg),
                )
                wallpaper.changeNoticeRes?.let { notice ->
                    Text(
                        text = stringResource(notice),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = NothingUiSpacing.Lg),
                    )
                }
                TextButton(
                    onClick = { runCatching { uriHandler.openUri(wallpaper.sourceUrl) } },
                    modifier = Modifier.heightIn(min = NothingUiSpacing.Xxxl),
                ) {
                    Text(
                        text = stringResource(R.string.dotwel_wallpaper_source) +
                            ": " + wallpaper.sourceUrl,
                    )
                }
                TextButton(
                    onClick = { runCatching { uriHandler.openUri(wallpaper.licenseUrl) } },
                    modifier = Modifier.heightIn(min = NothingUiSpacing.Xxxl),
                ) {
                    Text(
                        text = stringResource(R.string.dotwel_wallpaper_license) +
                            ": " + wallpaper.licenseUrl,
                    )
                }
                Button(
                    onClick = {
                        if (!applying) {
                            applying = true
                            messageRes = null
                            scope.launch {
                                try {
                                    messageRes = when (
                                        AmoledWallpaperApplier.apply(context, wallpaper)
                                    ) {
                                        is AmoledWallpaperApplyResult.Applied ->
                                            R.string.dotwel_wallpaper_applied

                                        AmoledWallpaperApplyResult.Unsupported ->
                                            R.string.dotwel_wallpaper_unsupported

                                        AmoledWallpaperApplyResult.NotAllowedByPolicy ->
                                            R.string.dotwel_wallpaper_not_allowed

                                        AmoledWallpaperApplyResult.SecurityDenied ->
                                            R.string.dotwel_wallpaper_security_denied

                                        AmoledWallpaperApplyResult.IoFailed ->
                                            R.string.dotwel_wallpaper_io_failed

                                        AmoledWallpaperApplyResult.Cancelled ->
                                            R.string.dotwel_wallpaper_failed

                                        is AmoledWallpaperApplyResult.Unconfirmed ->
                                            R.string.dotwel_wallpaper_unconfirmed

                                        is AmoledWallpaperApplyResult.Failed ->
                                            R.string.dotwel_wallpaper_failed
                                    }
                                } finally {
                                    applying = false
                                }
                            }
                        }
                    },
                    enabled = !applying && manager != null,
                    modifier = Modifier
                        .padding(horizontal = NothingUiSpacing.Lg, vertical = NothingUiSpacing.Sm)
                        .heightIn(min = NothingUiSpacing.Xxxl),
                ) {
                    Text(stringResource(R.string.dotwel_wallpaper_apply))
                }
                TextButton(
                    onClick = {
                        if (!applying) {
                            selectedId = null
                            messageRes = null
                        }
                    },
                    enabled = !applying,
                    modifier = Modifier
                        .padding(horizontal = NothingUiSpacing.Lg)
                        .heightIn(min = NothingUiSpacing.Xxxl),
                ) {
                    Text(stringResource(R.string.dotwel_wallpaper_cancel_preview))
                }
                messageRes?.let { res ->
                    Text(
                        text = stringResource(res),
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(
                            horizontal = NothingUiSpacing.Lg,
                            vertical = NothingUiSpacing.Sm,
                        ),
                    )
                }
            }
        }
        Spacer(modifier = Modifier.height(NothingUiSpacing.Xxl))
    }
}

@Composable
private fun WallpaperTile(
    wallpaper: AmoledWallpaper,
    selected: Boolean,
    enabled: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .selectable(
                selected = selected,
                enabled = enabled,
                role = Role.RadioButton,
                onClick = onSelect,
            )
            .heightIn(min = NothingUiSpacing.Xxxl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Surface(
            shape = RoundedCornerShape(NothingUiSpacing.Sm),
            color = NothingUiPalette.Black,
            border = BorderStroke(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.outline
                },
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp),
        ) {
            Image(
                painter = painterResource(wallpaper.drawableRes),
                contentDescription = stringResource(wallpaper.titleRes),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(180.dp)
                    .clip(RoundedCornerShape(NothingUiSpacing.Sm)),
            )
        }
        Text(
            text = stringResource(wallpaper.titleRes),
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = NothingUiSpacing.Sm),
        )
    }
}

@Composable
private fun AmoledWallpaperPreview(
    wallpaper: AmoledWallpaper,
    modifier: Modifier = Modifier,
) {
    Surface(
        shape = RoundedCornerShape(NothingUiSpacing.Md),
        color = NothingUiPalette.Black,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = NothingUiSpacing.Lg, vertical = NothingUiSpacing.Sm),
    ) {
        Row {
            Image(
                painter = painterResource(wallpaper.drawableRes),
                contentDescription = stringResource(wallpaper.titleRes),
                modifier = Modifier
                    .width(160.dp)
                    .height(300.dp)
                    .clip(RoundedCornerShape(NothingUiSpacing.Md)),
            )
            Spacer(modifier = Modifier.size(NothingUiSpacing.Lg))
        }
    }
}
