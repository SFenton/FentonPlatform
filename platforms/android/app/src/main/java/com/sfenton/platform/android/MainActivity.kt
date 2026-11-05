package com.sfenton.platform.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            FoundationTheme {
                FoundationDemo()
            }
        }
    }
}

@Composable
private fun FoundationTheme(content: @Composable () -> Unit) {
    MaterialTheme(content = content)
}

@Composable
private fun FoundationDemo() {
    val modalState = remember { FoundationModalState() }
    Button(
        modifier = Modifier.semantics {
            contentDescription = "Show foundation dialog"
        },
        onClick = modalState::open,
    ) {
        Text("Show dialog")
    }
    FoundationModalHost(
        state = modalState,
        title = "Window-scoped modal",
        message = "The modal state is owned by this composition.",
        dismissLabel = "Close",
    )
}
