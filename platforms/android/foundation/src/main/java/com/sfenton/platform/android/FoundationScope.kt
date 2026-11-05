package com.sfenton.platform.android

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/** Owns a cancellable lifecycle for one native host or feature. */
class FoundationScope(parent: CoroutineScope? = null) : AutoCloseable {
    private val job = SupervisorJob(parent?.coroutineContext?.get(kotlinx.coroutines.Job))
    val scope: CoroutineScope = CoroutineScope(
        (parent?.coroutineContext ?: Dispatchers.Main.immediate) + job,
    )

    fun child(): FoundationScope = FoundationScope(scope)

    override fun close() {
        scope.cancel()
    }
}
