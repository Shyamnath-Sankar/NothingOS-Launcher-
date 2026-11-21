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

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.android.launcher3.R

val DotoFontFamily = FontFamily(
    Font(R.font.doto_regular, FontWeight.Normal),
    Font(R.font.doto_bold, FontWeight.Bold),
)

private val BodyFontFamily = FontFamily.SansSerif

private val base = Typography()

val NothingUiTypography = Typography(
    displayLarge = base.displayLarge.copy(
        fontFamily = DotoFontFamily,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.sp,
    ),
    displayMedium = base.displayMedium.copy(
        fontFamily = DotoFontFamily,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.sp,
    ),
    displaySmall = base.displaySmall.copy(
        fontFamily = DotoFontFamily,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.sp,
    ),
    headlineLarge = base.headlineLarge.copy(fontFamily = BodyFontFamily),
    headlineMedium = base.headlineMedium.copy(fontFamily = BodyFontFamily),
    headlineSmall = base.headlineSmall.copy(fontFamily = BodyFontFamily),
    titleLarge = base.titleLarge.copy(fontFamily = BodyFontFamily),
    titleMedium = base.titleMedium.copy(fontFamily = BodyFontFamily),
    titleSmall = base.titleSmall.copy(fontFamily = BodyFontFamily),
    bodyLarge = base.bodyLarge.copy(fontFamily = BodyFontFamily),
    bodyMedium = base.bodyMedium.copy(fontFamily = BodyFontFamily),
    bodySmall = base.bodySmall.copy(fontFamily = BodyFontFamily),
    labelLarge = base.labelLarge.copy(fontFamily = BodyFontFamily),
    labelMedium = base.labelMedium.copy(fontFamily = BodyFontFamily),
    labelSmall = base.labelSmall.copy(fontFamily = BodyFontFamily),
    displayLargeEmphasized = base.displayLargeEmphasized.copy(
        fontFamily = DotoFontFamily,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.sp,
    ),
    displayMediumEmphasized = base.displayMediumEmphasized.copy(
        fontFamily = DotoFontFamily,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.sp,
    ),
    displaySmallEmphasized = base.displaySmallEmphasized.copy(
        fontFamily = DotoFontFamily,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.sp,
    ),
    headlineLargeEmphasized = base.headlineLargeEmphasized.copy(fontFamily = BodyFontFamily),
    headlineMediumEmphasized = base.headlineMediumEmphasized.copy(fontFamily = BodyFontFamily),
    headlineSmallEmphasized = base.headlineSmallEmphasized.copy(fontFamily = BodyFontFamily),
    titleLargeEmphasized = base.titleLargeEmphasized.copy(fontFamily = BodyFontFamily),
    titleMediumEmphasized = base.titleMediumEmphasized.copy(fontFamily = BodyFontFamily),
    titleSmallEmphasized = base.titleSmallEmphasized.copy(fontFamily = BodyFontFamily),
    bodyLargeEmphasized = base.bodyLargeEmphasized.copy(fontFamily = BodyFontFamily),
    bodyMediumEmphasized = base.bodyMediumEmphasized.copy(fontFamily = BodyFontFamily),
    bodySmallEmphasized = base.bodySmallEmphasized.copy(fontFamily = BodyFontFamily),
    labelLargeEmphasized = base.labelLargeEmphasized.copy(fontFamily = BodyFontFamily),
    labelMediumEmphasized = base.labelMediumEmphasized.copy(fontFamily = BodyFontFamily),
    labelSmallEmphasized = base.labelSmallEmphasized.copy(fontFamily = BodyFontFamily),
)

object NothingUiType {
    val NumericDisplay: TextStyle = TextStyle(
        fontFamily = DotoFontFamily,
        fontWeight = FontWeight.Bold,
        fontSize = 56.sp,
        lineHeight = 60.sp,
        letterSpacing = 0.sp,
    )

    val NumericLabel: TextStyle = TextStyle(
        fontFamily = DotoFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 20.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.sp,
    )
}
