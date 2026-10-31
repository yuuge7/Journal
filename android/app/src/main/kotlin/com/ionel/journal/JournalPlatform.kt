package com.ionel.journal

import android.Manifest
import android.app.*
import android.appwidget.AppWidgetManager
import android.content.*
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricPrompt
import android.location.LocationManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.*
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class JournalPlatform(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "journal/platform")
    private var permissionAction: (() -> Unit)? = null
    private var permissionResult: MethodChannel.Result? = null
    private var authResult: MethodChannel.Result? = null
    private var recorder: MediaRecorder? = null
    private var recordingPath: String? = null
    private var player: MediaPlayer? = null
    private val prefs = activity.getSharedPreferences("journal_platform", Context.MODE_PRIVATE)

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "launchAction" -> { val write = activity.intent.action == "com.ionel.journal.WRITE"; activity.intent.action = Intent.ACTION_MAIN; result.success(if (write) "write" else null) }
                    "secure" -> { if (call.argument<Boolean>("enabled") == true) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE); result.success(null) }
                    "authenticate" -> authenticate(result, call.argument<Boolean>("deviceCredentialOnly") == true)
                    "location" -> permission(Manifest.permission.ACCESS_FINE_LOCATION, result) { location(result) }
                    "startRecording" -> permission(Manifest.permission.RECORD_AUDIO, result) {
                        check(recorder == null) { "Already recording" }
                        val file = File(activity.cacheDir, "voice-${System.currentTimeMillis()}.m4a")
                        val audio = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(activity) else @Suppress("DEPRECATION") MediaRecorder()
                        audio.setAudioSource(MediaRecorder.AudioSource.MIC)
                        audio.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                        audio.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                        audio.setOutputFile(file.absolutePath)
                        audio.prepare(); audio.start(); recorder = audio; recordingPath = file.absolutePath
                        result.success(file.absolutePath)
                    }
                    "stopRecording" -> {
                        val audio = recorder; recorder = null
                        try { audio?.stop(); result.success(recordingPath) } finally { audio?.release(); recordingPath = null }
                    }
                    "play" -> { player?.release(); player = MediaPlayer().apply { setDataSource(call.argument<String>("path")!!); prepare(); setOnCompletionListener { it.release(); player = null }; start() }; result.success(null) }
                    "reminders" -> {
                        val days = call.argument<Int>("days") ?: 0
                        val enable = { prefs.edit().putInt("reminder_days", days).putLong("reminder_started", System.currentTimeMillis()).apply(); scheduleReminder(activity); result.success(null) }
                        if (days > 0 && Build.VERSION.SDK_INT >= 33) permission(Manifest.permission.POST_NOTIFICATIONS, result, enable)
                        else enable()
                    }
                    "backupSaved" -> { prefs.edit().putLong("last_backup", System.currentTimeMillis()).apply(); scheduleReminder(activity); result.success(null) }
                    "widget" -> { prefs.edit().putInt("streak", call.argument<Int>("streak") ?: 0).putBoolean("written", call.argument<Boolean>("written") == true).putString("day", java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())).apply(); JournalWidget.refresh(activity); result.success(null) }
                    "version" -> { val info = activity.packageManager.getPackageInfo(activity.packageName, 0); result.success("${info.versionName}+${if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode}") }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("PLATFORM", e.message, null) }
        }
    }
    fun openWriter() { channel.invokeMethod("write", null) }
    private fun permission(name: String, result: MethodChannel.Result, action: () -> Unit) {
        if (activity.checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED) { action(); return }
        if (permissionResult != null) { result.error("BUSY", "Another permission request is open", null); return }
        permissionAction = action; permissionResult = result
        activity.requestPermissions(if (name == Manifest.permission.ACCESS_FINE_LOCATION) arrayOf(name, Manifest.permission.ACCESS_COARSE_LOCATION) else arrayOf(name), 4930)
    }
    private fun location(result: MethodChannel.Result) {
        val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val last = manager.getProviders(true).mapNotNull { provider -> try { manager.getLastKnownLocation(provider) } catch (_: SecurityException) { null } }.maxByOrNull { it.time }
        fun deliver(value: android.location.Location) { result.success(String.format(java.util.Locale.US, "%.4f, %.4f", value.latitude, value.longitude)) }
        if (last != null && System.currentTimeMillis() - last.time < 300000) { deliver(last); return }
        val provider = when {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> { result.error("NO_FIX", "Turn on device location to add a place. Journal never requests it automatically.", null); return }
        }
        var finished = false
        val handler = Handler(Looper.getMainLooper())
        val listener = object : android.location.LocationListener {
            override fun onLocationChanged(location: android.location.Location) {
                if (finished) return
                finished = true; manager.removeUpdates(this); deliver(location)
            }
            @Deprecated("Android legacy callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        @Suppress("DEPRECATION") manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
        handler.postDelayed({ if (!finished) { finished = true; manager.removeUpdates(listener); result.error("NO_FIX", "No location fix yet. Try again outdoors.", null) } }, 15000)
    }
    fun onPermissionResult(code: Int, grants: IntArray) {
        if (code != 4930) return
        val action = permissionAction; val result = permissionResult; permissionAction = null; permissionResult = null
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) try { action?.invoke() } catch (e: Exception) { result?.error("PLATFORM", e.message, null) }
        else result?.error("DENIED", "Permission was not granted", null)
    }
    private fun authenticate(result: MethodChannel.Result, deviceCredentialOnly: Boolean) {
        if (authResult != null) { result.error("BUSY", "Unlock already open", null); return }
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!keyguard.isDeviceSecure) { result.error("NO_LOCK", "Set a device PIN, pattern or password in Android settings first.", null); return }
        authResult = result
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                val credentials = android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL
                val authenticators = if (deviceCredentialOnly) credentials else credentials or android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG
                BiometricPrompt.Builder(activity)
                    .setTitle("Unlock Journal")
                    .setAllowedAuthenticators(authenticators)
                    .build()
                    .authenticate(CancellationSignal(), activity.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) { finishAuthentication(result, true) }
                        override fun onAuthenticationError(code: Int, message: CharSequence) { finishAuthentication(result, false) }
                    })
            } else {
                @Suppress("DEPRECATION") val intent = keyguard.createConfirmDeviceCredentialIntent("Unlock Journal", "Use your device PIN, pattern or password")
                if (intent == null) {
                    authResult = null
                    result.error("NO_LOCK", "Set a device PIN, pattern or password in Android settings first.", null)
                    return
                }
                activity.startActivityForResult(intent, 4931)
            }
        } catch (e: Exception) {
            authResult = null
            throw e
        }
    }
    private fun finishAuthentication(result: MethodChannel.Result, authenticated: Boolean) {
        if (authResult !== result) return
        authResult = null
        result.success(authenticated)
    }
    fun onActivityResult(code: Int, resultCode: Int): Boolean {
        if (code != 4931) return false
        authResult?.success(resultCode == Activity.RESULT_OK); authResult = null; return true
    }
    companion object {
        fun scheduleReminder(context: Context) {
            val prefs = context.getSharedPreferences("journal_platform", Context.MODE_PRIVATE)
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = PendingIntent.getBroadcast(context, 41, Intent(context, BackupReminder::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            alarm.cancel(intent)
            val days = prefs.getInt("reminder_days", 0)
            if (days <= 0) return
            val last = prefs.getLong("last_backup", 0).let { if (it == 0L) prefs.getLong("reminder_started", System.currentTimeMillis()) else it }
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, maxOf(System.currentTimeMillis() + 60000, last + days.toLong() * 86400000), intent)
        }
    }
}

class BackupReminder : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) { JournalPlatform.scheduleReminder(context); return }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("backup", "Backup reminders", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(context, 42, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, "backup") else @Suppress("DEPRECATION") Notification.Builder(context)).setSmallIcon(R.drawable.ic_notification).setContentTitle("Keep a copy of your journal").setContentText("It is time to export a backup. Your writing stays on your device.").setContentIntent(open).setAutoCancel(true).build()
        if (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) manager.notify(41, notification)
    }
}
