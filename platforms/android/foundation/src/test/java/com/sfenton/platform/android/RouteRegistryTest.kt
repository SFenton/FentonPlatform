package com.sfenton.platform.android

import androidx.compose.runtime.Composable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RouteRegistryTest {
    @Test
    fun routesRemainConsumerInjected() {
        val registry = RouteRegistry(
            listOf(
                FoundationRoute("home", @Composable {}),
                FoundationRoute("settings", @Composable {}),
            ),
        )

        assertEquals(2, registry.routes.size)
        assertEquals("home", registry.find("home")?.key)
        assertNull(registry.find("missing"))
    }
}
