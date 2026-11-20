package com.sfenton.platform.android

import kotlinx.coroutines.Job
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FoundationScopeTest {
    @Test
    fun closingParentCancelsChildScope() = runTest {
        val parent = FoundationScope(this)
        val child = parent.child()

        parent.close()

        assertTrue((child.scope.coroutineContext[Job])?.isCancelled == true)
        assertFalse((parent.scope.coroutineContext[Job])?.isActive == true)
        child.close()
    }
}
