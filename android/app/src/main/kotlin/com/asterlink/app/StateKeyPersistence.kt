package com.asterlink.app

import android.content.Context

internal object StateKeyPersistence {
    fun flush(context: Context, namespace: String?): Boolean {
        require(namespace == null || Regex("^state_[a-f0-9]{32}$").matches(namespace))
        val data = namespace ?: "FlutterSecureStorage"
        val wrapped = if (namespace == null) "FlutterSecureKeyStorage"
            else "FlutterSecureKeyStorage:$namespace"
        // flutter_secure_storage 11 uses apply(). A changed marker and commit()
        // persist the complete current map and wait for pending writes.
        val names = listOf(wrapped, "FlutterSecureStorageConfiguration:$data", data)
        return names.map { name ->
            context.getSharedPreferences(name, Context.MODE_PRIVATE).edit()
                .putLong("_wenxi_state_flush_v1", System.nanoTime())
                .commit()
        }.all { it }
    }
}
