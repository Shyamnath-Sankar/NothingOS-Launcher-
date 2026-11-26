/*
 * Copyright 2022, Lawnchair
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

package app.lawnchair.ui.preferences.about.acknowledgements

import android.content.Intent
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.lawnchair.ui.preferences.components.controls.ClickablePreference
import app.lawnchair.ui.preferences.components.layout.PreferenceGroupHeading
import app.lawnchair.ui.preferences.components.layout.PreferenceLayoutLazyColumn
import app.lawnchair.ui.preferences.components.layout.preferenceGroupItems
import com.android.launcher3.R

@Composable
fun Acknowledgements(
    modifier: Modifier = Modifier,
    viewModel: AcknowledgementsViewModel = viewModel(),
) {
    val ossLibraries by viewModel.ossLibraries.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var licenseText by remember { mutableStateOf<Int?>(null) }

    licenseText?.let { rawRes ->
        val text = remember(rawRes) {
            context.resources.openRawResource(rawRes).bufferedReader().use { it.readText() }
        }
        AlertDialog(
            onDismissRequest = { licenseText = null },
            title = { Text(stringResource(R.string.dotwel_license_title)) },
            text = { Text(text) },
            confirmButton = {
                TextButton(onClick = { licenseText = null }) {
                    Text(stringResource(R.string.dotwel_license_close))
                }
            },
        )
    }

    PreferenceLayoutLazyColumn(
        label = stringResource(id = R.string.acknowledgements),
        modifier = modifier,
    ) {
        item {
            PreferenceGroupHeading(stringResource(R.string.dotwel_credits_heading))
        }
        item {
            ClickablePreference(
                label = stringResource(R.string.dotwel_credits_awesome),
                subtitle = "MIT",
                onClick = { licenseText = R.raw.awesomeawidgets_mit },
            )
        }
        item {
            ClickablePreference(
                label = stringResource(R.string.dotwel_credits_kwgt),
                subtitle = "MIT",
                onClick = { licenseText = R.raw.kwgt_widgets_mit },
            )
        }
        item {
            Spacer(Modifier.height(8.dp))
        }
        preferenceGroupItems(ossLibraries, isFirstChild = false) { _, library ->
            OssLibraryItem(
                name = library.name,
                license = library.license,
            )
        }
    }
}

@Composable
fun OssLibraryItem(
    name: String,
    license: OssLibrary.License?,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    ClickablePreference(
        label = name,
        modifier = modifier,
        subtitle = license?.name,
        onClick = {
            license?.url?.let { urlString ->
                val webpage = urlString.toUri()
                val intent = Intent(Intent.ACTION_VIEW, webpage)
                if (intent.resolveActivity(context.packageManager) != null) {
                    context.startActivity(intent)
                }
            }
        },
    )
}
