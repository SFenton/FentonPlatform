package com.sfenton.platform.android

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf

/** Minimal modal state owned by one composition/window. */
class FoundationModalState {
    internal val isOpen: MutableState<Boolean> = mutableStateOf(false)

    fun open() {
        isOpen.value = true
    }

    fun close() {
        isOpen.value = false
    }
}

@Composable
fun FoundationModalHost(
    state: FoundationModalState,
    title: String,
    message: String,
    dismissLabel: String,
) {
    if (state.isOpen.value) {
        AlertDialog(
            onDismissRequest = state::close,
            title = { Text(title) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = state::close) {
                    Text(dismissLabel)
                }
            },
        )
    }
}
