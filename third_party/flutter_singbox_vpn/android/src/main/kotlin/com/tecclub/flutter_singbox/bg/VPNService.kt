package com.tecclub.flutter_singbox.bg

import android.content.Intent
import android.content.pm.PackageManager.NameNotFoundException
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.util.Log
import com.tecclub.flutter_singbox.Application
import com.tecclub.flutter_singbox.constant.Alert
import io.nekohasekai.libbox.TunOptions
import com.tecclub.flutter_singbox.ktx.toIpPrefix
import com.tecclub.flutter_singbox.ktx.toList
import com.tecclub.flutter_singbox.database.Settings
import io.nekohasekai.libbox.Libbox
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.io.FileDescriptor
import java.net.InetAddress

class VPNService : VpnService(), PlatformInterfaceWrapper {

    companion object {
        private const val TAG = "VPNService"
    }

    private val service = BoxService(this, this)
    var systemProxyAvailable = false
    var systemProxyEnabled = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null && intent.action == BoxService.ACTION_START) {
            val configContent = intent.getStringExtra(BoxService.EXTRA_CONFIG_CONTENT)
            if (configContent != null) {
                com.tecclub.flutter_singbox.config.SimpleConfigManager.saveConfig(configContent)
            }
        }
        return service.onStartCommand()
    }

    override fun onBind(intent: Intent): IBinder {
        val binder = super.onBind(intent)
        if (binder != null) {
            return binder
        }
        return service.onBind()
    }

    override fun onDestroy() {
        service.onDestroy()
        super.onDestroy()
    }

    override fun onRevoke() {
        service.onRevoke()
        super.onRevoke()
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        android.util.Log.d("VPNService", "autoDetectInterfaceControl called with fd=$fd")
        val result = protect(fd)
        android.util.Log.d("VPNService", "protect($fd) returned $result")
    }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("android: missing vpn permission")

        val builder = Builder()
            .setSession("sing-box")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        // Snapshot Libbox iterators before use. Some gomobile iterators make
        // a second hasNext()/pass unreliable after partial consumption.
        val inet4Addresses = mutableListOf<io.nekohasekai.libbox.RoutePrefix>()
        val inet4Address = options.inet4Address
        while (inet4Address.hasNext()) {
            inet4Addresses.add(inet4Address.next())
        }
        for (address in inet4Addresses) {
            builder.addAddress(address.address(), address.prefix())
        }
        val hasInet4Address = inet4Addresses.isNotEmpty()

        val inet6Addresses = mutableListOf<io.nekohasekai.libbox.RoutePrefix>()
        val inet6Address = options.inet6Address
        while (inet6Address.hasNext()) {
            inet6Addresses.add(inet6Address.next())
        }
        for (address in inet6Addresses) {
            builder.addAddress(address.address(), address.prefix())
        }
        val hasInet6Address = inet6Addresses.isNotEmpty()

        if (options.autoRoute) {
            builder.addDnsServer(options.dnsServerAddress.value)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val inet4Routes = mutableListOf<io.nekohasekai.libbox.RoutePrefix>()
                val inet4RouteAddress = options.inet4RouteAddress
                while (inet4RouteAddress.hasNext()) {
                    inet4Routes.add(inet4RouteAddress.next())
                }
                if (inet4Routes.isNotEmpty()) {
                    for (route in inet4Routes) {
                        builder.addRoute(route.toIpPrefix())
                    }
                } else if (hasInet4Address) {
                    builder.addRoute("0.0.0.0", 0)
                }

                val inet6Routes = mutableListOf<io.nekohasekai.libbox.RoutePrefix>()
                val inet6RouteAddress = options.inet6RouteAddress
                while (inet6RouteAddress.hasNext()) {
                    inet6Routes.add(inet6RouteAddress.next())
                }
                if (inet6Routes.isNotEmpty()) {
                    for (route in inet6Routes) {
                        builder.addRoute(route.toIpPrefix())
                    }
                } else if (hasInet6Address) {
                    builder.addRoute("::", 0)
                }

                val inet4RouteExcludeAddress = options.inet4RouteExcludeAddress
                while (inet4RouteExcludeAddress.hasNext()) {
                    builder.excludeRoute(inet4RouteExcludeAddress.next().toIpPrefix())
                }

                val inet6RouteExcludeAddress = options.inet6RouteExcludeAddress
                while (inet6RouteExcludeAddress.hasNext()) {
                    builder.excludeRoute(inet6RouteExcludeAddress.next().toIpPrefix())
                }
            } else {
                val inet4Routes = mutableListOf<io.nekohasekai.libbox.RoutePrefix>()
                val inet4RouteAddress = options.inet4RouteRange
                while (inet4RouteAddress.hasNext()) {
                    inet4Routes.add(inet4RouteAddress.next())
                }
                if (inet4Routes.isNotEmpty()) {
                    for (address in inet4Routes) {
                        builder.addRoute(address.address(), address.prefix())
                    }
                } else if (hasInet4Address) {
                    builder.addRoute("0.0.0.0", 0)
                }

                val inet6Routes = mutableListOf<io.nekohasekai.libbox.RoutePrefix>()
                val inet6RouteAddress = options.inet6RouteRange
                while (inet6RouteAddress.hasNext()) {
                    inet6Routes.add(inet6RouteAddress.next())
                }
                if (inet6Routes.isNotEmpty()) {
                    for (address in inet6Routes) {
                        builder.addRoute(address.address(), address.prefix())
                    }
                } else if (hasInet6Address) {
                    builder.addRoute("::", 0)
                }
            }

            if (Settings.perAppProxyEnabled) {
                val appList = Settings.perAppProxyList
                if (Settings.perAppProxyMode == Settings.PER_APP_PROXY_INCLUDE) {
                    appList.forEach {
                        try {
                            builder.addAllowedApplication(it)
                        } catch (_: NameNotFoundException) {
                        }
                    }
                    builder.addAllowedApplication(packageName)
                } else {
                    appList.forEach {
                        try {
                            builder.addDisallowedApplication(it)
                        } catch (_: NameNotFoundException) {
                        }
                    }
                }
            } else {
                val includePackage = options.includePackage
                if (includePackage.hasNext()) {
                    while (includePackage.hasNext()) {
                        try {
                            builder.addAllowedApplication(includePackage.next())
                        } catch (_: NameNotFoundException) {
                        }
                    }
                }

                val excludePackage = options.excludePackage
                if (excludePackage.hasNext()) {
                    while (excludePackage.hasNext()) {
                        try {
                            builder.addDisallowedApplication(excludePackage.next())
                        } catch (_: NameNotFoundException) {
                        }
                    }
                }
            }
        }

        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            systemProxyAvailable = true
            systemProxyEnabled = Settings.systemProxyEnabled
            if (systemProxyEnabled) builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    options.httpProxyServer,
                    options.httpProxyServerPort,
                    options.httpProxyBypassDomain.toList()
                )
            )
        } else {
            systemProxyAvailable = false
            systemProxyEnabled = false
        }

        val pfd =
            builder.establish() ?: error("android: the application is not prepared or is revoked")
        service.fileDescriptor = pfd
        return pfd.fd
    }
    
    override fun protect(fd: Int): Boolean {
        return super.protect(fd)
    }
    
    override fun writeLog(message: String) {
        service.writeLog(message)
    }
    
    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {
        service.sendNotification(notification)
    }
}