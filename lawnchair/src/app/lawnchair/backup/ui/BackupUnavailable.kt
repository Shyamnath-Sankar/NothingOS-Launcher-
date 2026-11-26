package app.lawnchair.backup.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.android.launcher3.R

@Composable
fun BackupUnavailableNotice(modifier: Modifier = Modifier) {
    Text(
        text = stringResource(R.string.backup_temporarily_unavailable),
        style = MaterialTheme.typography.bodyLarge,
        modifier = modifier.padding(horizontal = 24.dp, vertical = 16.dp),
    )
}
