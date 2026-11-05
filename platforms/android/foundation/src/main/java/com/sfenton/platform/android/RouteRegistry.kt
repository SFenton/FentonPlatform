package com.sfenton.platform.android

/** A consumer-owned route definition; the foundation does not own app navigation state. */
data class FoundationRoute(val key: String, val content: @androidx.compose.runtime.Composable () -> Unit)

class RouteRegistry(routes: List<FoundationRoute>) {
    private val routesByKey = routes.associateBy { it.key }

    val routes: List<FoundationRoute> = routesByKey.values.toList()

    fun find(key: String): FoundationRoute? = routesByKey[key]
}
