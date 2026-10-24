package com.lifeos.home_organizer

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), QuickOverlay.Listener {
    private var overlayChannel: MethodChannel? = null

    /// Действие, с которым оверлей запустил приложение до старта Flutter.
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) pendingAction = takeOverlayAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeOverlayAction(intent)?.let(::onOverlayAction)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "canDrawOverlays" -> result.success(QuickOverlay.canDraw(this))
                "requestPermission" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(null)
                }
                "show" -> {
                    val items = (call.argument<List<Map<String, Any?>>>("items") ?: emptyList())
                        .map {
                            QuickOverlay.Item(
                                id = it["id"] as String,
                                label = it["label"] as String,
                                color = (it["color"] as Number).toInt(),
                            )
                        }
                    result.success(
                        QuickOverlay.show(
                            application,
                            items,
                            isLeft = call.argument<Boolean>("isLeft") ?: false,
                            fraction = call.argument<Double>("fraction") ?: 0.6,
                            hideWhenAppVisible = call.argument<Boolean>("hideWhenAppVisible") ?: true,
                        ),
                    )
                }
                "hide" -> {
                    QuickOverlay.hide()
                    result.success(null)
                }
                "takePendingAction" -> {
                    result.success(pendingAction)
                    pendingAction = null
                }
                else -> result.notImplemented()
            }
        }
        overlayChannel = channel
        QuickOverlay.listener = this
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (QuickOverlay.listener === this) QuickOverlay.listener = null
        overlayChannel?.setMethodCallHandler(null)
        overlayChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        QuickOverlay.setAppVisible(true)
    }

    override fun onStop() {
        QuickOverlay.setAppVisible(false)
        super.onStop()
    }

    override fun onOverlayAction(id: String) {
        overlayChannel?.invokeMethod("onAction", mapOf("id" to id))
    }

    override fun onOverlayDismissed() {
        overlayChannel?.invokeMethod("onDismissed", null)
    }

    override fun onOverlayMoved(isLeft: Boolean, fraction: Double) {
        overlayChannel?.invokeMethod(
            "onMoved",
            mapOf("isLeft" to isLeft, "fraction" to fraction),
        )
    }

    private fun takeOverlayAction(intent: Intent?): String? {
        val id = intent?.getStringExtra(QuickOverlay.EXTRA_ACTION) ?: return null
        intent.removeExtra(QuickOverlay.EXTRA_ACTION)
        // Запуск из «Недавних» повторяет исходный интент — действие уже было.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        return id
    }

    companion object {
        private const val CHANNEL = "lifeos/system_overlay"
    }
}
