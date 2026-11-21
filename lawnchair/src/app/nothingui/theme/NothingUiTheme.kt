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

package app.nothingui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

@Composable
fun NothingUiTheme(
    darkTheme: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colors = if (darkTheme) DarkNothingUiColors else LightNothingUiColors
    CompositionLocalProvider(LocalNothingUiColors provides colors) {
        MaterialTheme(
            colorScheme = if (darkTheme) colors.toDarkColorScheme() else colors.toLightColorScheme(),
            typography = NothingUiTypography,
            content = content,
        )
    }
}
