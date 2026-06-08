package com.video.rd.editor

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.view.LayoutInflater
import android.widget.Button
import android.widget.ImageView
import android.widget.RatingBar
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import com.google.android.gms.ads.nativead.MediaView
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val CHANNEL = "com.video.rd.editor/export_service"
        const val EXIT_AD_FACTORY_ID = "exitDialogAd"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var exportChannel: MethodChannel? = null
    // Set to true when the notification tap intent arrives; consumed in onResume
    // once Flutter is fully active and ready to handle navigation.
    private var pendingShowProgress = false

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        pendingPermissionResult?.success(isGranted)
        pendingPermissionResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Handle the case where the Activity was (re)created from a notification tap.
        if (intent?.action == ExportForegroundService.ACTION_OPEN_PROGRESS) {
            pendingShowProgress = true
        }

        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            EXIT_AD_FACTORY_ID,
            ExitDialogNativeAdFactory(this)
        )

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        exportChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {

                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (ContextCompat.checkSelfPermission(
                                this, Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        pendingPermissionResult = result
                        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }

                    "startExportService" -> {
                        val intent = Intent(this, ExportForegroundService::class.java).apply {
                            action = ExportForegroundService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }

                    "stopExportService" -> {
                        val intent = Intent(this, ExportForegroundService::class.java).apply {
                            action = ExportForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }

                    "updateExportProgress" -> {
                        val progress = (call.argument<Double>("progress") ?: 0.0)
                            .times(100).toInt().coerceIn(0, 100)
                        val intent = Intent(this, ExportForegroundService::class.java).apply {
                            action = ExportForegroundService.ACTION_UPDATE
                            putExtra(ExportForegroundService.EXTRA_PROGRESS, progress)
                        }
                        startService(intent)
                        result.success(null)
                    }

                    "shareToInstagramDirect" -> {
                        val filePath = call.argument<String>("filePath")
                        val mimeType = call.argument<String>("mimeType") ?: "video/mp4"
                        if (filePath == null) {
                            result.error("INVALID_ARG", "filePath is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(filePath)
                            val uri: Uri = FileProvider.getUriForFile(
                                this,
                                "com.video.rd.editor.fileprovider",
                                file
                            )
                            val dmIntent = Intent("com.instagram.share.ADD_TO_DIRECT").apply {
                                setDataAndType(uri, mimeType)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                setPackage("com.instagram.android")
                            }
                            grantUriPermission(
                                "com.instagram.android", uri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION
                            )
                            val resolveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.resolveActivity(
                                    dmIntent,
                                    PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.resolveActivity(dmIntent, PackageManager.MATCH_DEFAULT_ONLY)
                            }
                            if (resolveInfo != null) {
                                startActivity(dmIntent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("SHARE_ERROR", e.message, null)
                        }
                    }

                    "shareToInstagramStory" -> {
                        val filePath = call.argument<String>("filePath")
                        val mimeType = call.argument<String>("mimeType") ?: "video/mp4"
                        if (filePath == null) {
                            result.error("INVALID_ARG", "filePath is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(filePath)
                            val uri: Uri = FileProvider.getUriForFile(
                                this,
                                "com.video.rd.editor.fileprovider",
                                file
                            )
                            val storyIntent = Intent("com.instagram.share.ADD_TO_STORY").apply {
                                setDataAndType(uri, mimeType)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                setPackage("com.instagram.android")
                            }
                            // Explicitly grant read permission to Instagram
                            grantUriPermission(
                                "com.instagram.android", uri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION
                            )
                            val resolveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.resolveActivity(
                                    storyIntent,
                                    PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.resolveActivity(storyIntent, PackageManager.MATCH_DEFAULT_ONLY)
                            }
                            if (resolveInfo != null) {
                                startActivity(storyIntent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("SHARE_ERROR", e.message, null)
                        }
                    }

                    "shareToApp" -> {
                        val filePath = call.argument<String>("filePath")
                        val targetPackage = call.argument<String>("package")
                        val mimeType = call.argument<String>("mimeType") ?: "video/mp4"
                        if (filePath == null || targetPackage == null) {
                            result.error("INVALID_ARG", "filePath and package are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(filePath)
                            val uri: Uri = FileProvider.getUriForFile(
                                this,
                                "com.video.rd.editor.fileprovider",
                                file
                            )
                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                type = mimeType
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                setPackage(targetPackage)
                            }
                            // Check if the target app is installed and can handle the intent
                            val resolveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.resolveActivity(
                                    shareIntent,
                                    PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.resolveActivity(shareIntent, PackageManager.MATCH_DEFAULT_ONLY)
                            }
                            if (resolveInfo != null) {
                                startActivity(shareIntent)
                                result.success(true)
                            } else {
                                // App not installed — let Flutter fall back to generic share
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("SHARE_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == ExportForegroundService.ACTION_OPEN_PROGRESS) {
            pendingShowProgress = true
        }
    }

    override fun onResume() {
        super.onResume()
        if (pendingShowProgress) {
            pendingShowProgress = false
            // Post to the next looper frame so Flutter's engine is fully resumed
            // and ready to process the method channel call before we send it.
            android.os.Handler(mainLooper).post {
                exportChannel?.invokeMethod("onExportNotificationTap", null)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, EXIT_AD_FACTORY_ID)
        exportChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

class ExitDialogNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.native_exit_ad, null) as NativeAdView

        val mediaView = adView.findViewById<MediaView>(R.id.ad_media)
        val iconView = adView.findViewById<ImageView>(R.id.ad_icon)
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        val starsView = adView.findViewById<RatingBar>(R.id.ad_stars)
        val ctaView = adView.findViewById<Button>(R.id.ad_call_to_action)

        adView.mediaView = mediaView

        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView

        val icon = nativeAd.icon
        if (icon != null) {
            iconView.setImageDrawable(icon.drawable)
            adView.iconView = iconView
        } else {
            iconView.visibility = android.view.View.GONE
        }

        val starRating = nativeAd.starRating
        if (starRating != null) {
            starsView.rating = starRating.toFloat()
            adView.starRatingView = starsView
        } else {
            starsView.visibility = android.view.View.GONE
        }

        val cta = nativeAd.callToAction
        if (cta != null) {
            ctaView.text = cta
            adView.callToActionView = ctaView
        }

        adView.setNativeAd(nativeAd)
        return adView
    }
}
