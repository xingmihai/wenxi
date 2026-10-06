package com.asterlink.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import java.util.Locale

internal object ClientEnvironment {
    @Suppress("DEPRECATION")
    fun read(context: Context): Map<String, Any> {
        val values = mutableMapOf<String, Any>(
            "model" to Build.MODEL,
            "osVersion" to Build.VERSION.RELEASE,
        )
        try {
            val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return values
            val network = manager.activeNetwork ?: return values
            val caps = manager.getNetworkCapabilities(network) ?: return values
            val cellular = caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
            val info = if (cellular) manager.activeNetworkInfo else null
            val type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                cellular -> info?.extraInfo?.lowercase(Locale.ROOT).orEmpty()
                else -> ""
            }
            if (type.isNotEmpty()) {
                values["networkType"] = type
                values["networkSubtype"] = if (cellular && type != "vpn") info?.subtype ?: 0 else 0
            }
        } catch (_: SecurityException) {
            // Restricted devices may withhold network details; omit them.
        }
        return values
    }
}
