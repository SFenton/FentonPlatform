package com.sfenton.platform.android

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Rule
import org.junit.Test

class FoundationUiTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun modalHostOpensAndClosesInNativeCompose() {
        composeRule.setContent {
            val modalState = androidx.compose.runtime.remember { FoundationModalState() }
            androidx.compose.material3.TextButton(onClick = modalState::open) {
                androidx.compose.material3.Text("Open")
            }
            FoundationModalHost(modalState, "Title", "Message", "Close")
        }

        composeRule.onNodeWithText("Open").performClick()
        composeRule.onNodeWithText("Title").assertExists()
        composeRule.onNodeWithText("Close").performClick()
        composeRule.onNodeWithText("Title").assertDoesNotExist()
    }
}
