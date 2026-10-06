package com.asterlink.app

import android.content.Context
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 33], manifest = Config.NONE)
class StateKeyPersistenceTest {
    @Test fun flushesLegacyAndIsolatedStoresWithoutRemovingExistingRecords() {
        val context = RuntimeEnvironment.getApplication()
        for (namespace in listOf(null, "state_" + "a".repeat(32))) {
            val data = namespace ?: "FlutterSecureStorage"
            val wrapped = if (namespace == null) "FlutterSecureKeyStorage"
                else "FlutterSecureKeyStorage:$namespace"
            val names = listOf(data, wrapped, "FlutterSecureStorageConfiguration:$data")
            names.forEach { name ->
                context.getSharedPreferences(name, Context.MODE_PRIVATE).edit()
                    .putString("fixture", "encrypted-fixture")
                    .apply()
            }
            assertTrue(StateKeyPersistence.flush(context, namespace))
            names.forEach { name ->
                val preferences = context.getSharedPreferences(name, Context.MODE_PRIVATE)
                assertEquals("encrypted-fixture", preferences.getString("fixture", null))
                assertTrue(preferences.contains("_wenxi_state_flush_v1"))
                // Read the XML itself: an in-memory getString() can succeed
                // even when apply() has not persisted anything before a stop.
                // Robolectric escapes ':' on Windows, so use the actual
                // backing file instead of reconstructing its Android path.
                val disk: File = ReflectionHelpers.getField(preferences, "mFile")
                val xml = disk.readText()
                assertTrue(xml.contains("encrypted-fixture"))
                assertTrue(xml.contains("_wenxi_state_flush_v1"))
            }
        }
    }

    @Test fun refusesUnrelatedOrInvalidNamespaces() {
        val context = RuntimeEnvironment.getApplication()
        for (namespace in listOf("../other", "unrelated", "", "state_abc")) {
            try {
                StateKeyPersistence.flush(context, namespace)
                fail("Unexpected namespace accepted")
            } catch (_: IllegalArgumentException) {}
        }
    }
}
