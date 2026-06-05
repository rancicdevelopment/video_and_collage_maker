package com.video.rd.editor

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.LayoutInflater
import android.widget.Button
import android.widget.ImageView
import android.widget.RatingBar
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import com.google.android.gms.ads.nativead.MediaView
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val CHANNEL = "com.video.rd.editor/export_service"
        const val EXIT_AD_FACTORY_ID = "exitDialogAd"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        pendingPermissionResult?.success(isGranted)
        pendingPermissionResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            EXIT_AD_FACTORY_ID,
            ExitDialogNativeAdFactory(this)
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
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

                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, EXIT_AD_FACTORY_ID)
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
