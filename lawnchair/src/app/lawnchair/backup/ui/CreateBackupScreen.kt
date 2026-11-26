package app.lawnchair.backup.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.lawnchair.ui.preferences.LocalIsExpandedScreen
import app.lawnchair.ui.preferences.components.layout.PreferenceGroup
import app.lawnchair.ui.preferences.components.layout.PreferenceLayout
import com.android.launcher3.R

@Composable
fun CreateBackupScreen(
    modifier: Modifier = Modifier,
) {
    PreferenceLayout(
        label = stringResource(id = R.string.create_backup),
        modifier = modifier,
        isExpandedScreen = true,
        backArrowVisible = !LocalIsExpandedScreen.current,
    ) {
        PreferenceGroup {
            BackupUnavailableNotice()
        }
    }
}
