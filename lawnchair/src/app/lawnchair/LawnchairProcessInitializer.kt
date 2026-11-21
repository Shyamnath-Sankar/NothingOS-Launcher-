package app.lawnchair

import android.content.Context
import androidx.annotation.Keep
import app.lawnchair.bugreport.LawnchairBugReporter
import app.lawnchair.theme.color.tokens.ColorTokens
import app.nothingui.icons.NothingUiIconColors
import app.nothingui.theme.NothingUiFeature
import com.android.launcher3.Utilities
import com.android.launcher3.icons.mono.ThemedIconDrawable
import com.android.quickstep.QuickstepProcessInitializer

@Keep
class LawnchairProcessInitializer(context: Context) : QuickstepProcessInitializer(context) {

    override fun init(context: Context) {
        LawnchairBugReporter.INSTANCE.get(context)
        ThemedIconDrawable.COLORS_LOADER = {
            if (NothingUiFeature.homeEnabled) {
                // The Play home is monochrome. This loader is process-wide and is also used by
                // inherited consumers (e.g. themed clock icons), so resolve the neutral pair here
                // instead of leaving them on the wallpaper-derived accent swatches.
                NothingUiIconColors.forContext(it)
            } else if (Utilities.isDarkTheme(it)) {
                intArrayOf(
                    ColorTokens.Accent2_800.resolveColor(it),
                    ColorTokens.Accent1_200.resolveColor(it),
                )
            } else {
                intArrayOf(
                    ColorTokens.Accent1_100.resolveColor(it),
                    ColorTokens.Accent1_700.resolveColor(it),
                )
            }
        }
        super.init(context)
    }
}
