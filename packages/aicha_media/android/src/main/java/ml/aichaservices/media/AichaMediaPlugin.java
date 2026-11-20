package ml.aichaservices.media;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.media.AudioAttributes;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkInfo;
import android.os.Handler;
import android.os.Looper;
import android.media.AudioManager;
import android.media.ToneGenerator;
import android.net.Uri;
import android.provider.Settings;
import android.view.WindowManager;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.MediaPlayer;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.os.Vibrator;
import android.media.MediaRecorder;
import android.os.Build;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Micro (MediaRecorder, AAC .m4a) et lecture (MediaPlayer). */
public class AichaMediaPlugin implements FlutterPlugin, ActivityAware,
        MethodChannel.MethodCallHandler {

    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private MediaRecorder recorder;
    private MediaPlayer player;
    private Ringtone ringtone;
    private Vibrator vibrator;
    private ToneGenerator tone;
    private ConnectivityManager.NetworkCallback netCallback;
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "aicha_media");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        releaseRecorder();
        releasePlayer();
        stopRing();
        stopTone();
        stopNet();
    }

    /** true si Internet fonctionne vraiment (réseau validé par Android). */
    private boolean isOnline() {
        try {
            ConnectivityManager cm = (ConnectivityManager)
                    context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) return true;
            if (Build.VERSION.SDK_INT >= 23) {
                Network n = cm.getActiveNetwork();
                if (n == null) return false;
                NetworkCapabilities c = cm.getNetworkCapabilities(n);
                return c != null
                        && c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                        && c.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
            }
            NetworkInfo i = cm.getActiveNetworkInfo();
            return i != null && i.isConnected();
        } catch (Exception e) {
            return true;
        }
    }

    private void sendNet() {
        main.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (channel != null) channel.invokeMethod("net", isOnline());
            }
        }, 300);
    }

    private void watchNet() {
        if (netCallback != null || Build.VERSION.SDK_INT < 24) return;
        try {
            ConnectivityManager cm = (ConnectivityManager)
                    context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) return;
            netCallback = new ConnectivityManager.NetworkCallback() {
                @Override public void onAvailable(Network network) { sendNet(); }
                @Override public void onLost(Network network) { sendNet(); }
                @Override public void onCapabilitiesChanged(Network network,
                        NetworkCapabilities caps) { sendNet(); }
            };
            cm.registerDefaultNetworkCallback(netCallback);
        } catch (Exception ignored) { netCallback = null; }
    }

    private void stopNet() {
        if (netCallback == null) return;
        try {
            ConnectivityManager cm = (ConnectivityManager)
                    context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm != null) cm.unregisterNetworkCallback(netCallback);
        } catch (Exception ignored) { }
        netCallback = null;
    }

    private void stopTone() {
        if (tone != null) {
            try { tone.stopTone(); } catch (Exception ignored) { }
            try { tone.release(); } catch (Exception ignored) { }
            tone = null;
        }
    }

    private void stopRing() {
        if (ringtone != null) {
            try { ringtone.stop(); } catch (Exception ignored) { }
            ringtone = null;
        }
        if (vibrator != null) {
            try { vibrator.cancel(); } catch (Exception ignored) { }
            vibrator = null;
        }
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }

    private static final int CALL_NOTIF_ID = 7312;
    private static final String CALL_CHANNEL = "aicha_calls";

    /** Appel entrant quand l'application est fermée : notification plein écran
     *  avec sonnerie, qui ouvre l'application. */
    private void showIncomingCall(String callId, String title, String body) {
        IncomingCall.show(context, callId, title);
    }

    private static final int BADGE_NOTIF_ID = 7314;
    private static final String BADGE_CHANNEL = "aicha_badge";

    /** Pastille sur l'icône : notification discrète (sans son) avec le total.
     *  Le lanceur du téléphone affiche le chiffre sur l'icône de l'appli. */
    private void setBadge(int count, String text) {
        try {
            NotificationManager nm = (NotificationManager)
                    context.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            if (count <= 0) {
                nm.cancel(BADGE_NOTIF_ID);
                return;
            }
            if (Build.VERSION.SDK_INT >= 26) {
                NotificationChannel ch = new NotificationChannel(BADGE_CHANNEL,
                        "Nouveautés (pastille)", NotificationManager.IMPORTANCE_LOW);
                ch.setDescription("Nombre de messages, appels et commandes non vus");
                ch.setShowBadge(true);
                ch.setSound(null, null);
                ch.enableVibration(false);
                nm.createNotificationChannel(ch);
            }
            Intent launch = context.getPackageManager()
                    .getLaunchIntentForPackage(context.getPackageName());
            if (launch == null) return;
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
            PendingIntent pi = PendingIntent.getActivity(context, 7315, launch, flags);
            Notification.Builder b = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(context, BADGE_CHANNEL)
                    : new Notification.Builder(context);
            int icon = context.getApplicationInfo().icon;
            b.setSmallIcon(icon == 0 ? android.R.drawable.stat_notify_chat : icon)
                    .setContentTitle("Aïcha Services")
                    .setContentText(text == null ? "Vous avez des nouveautés" : text)
                    .setNumber(count)
                    .setOnlyAlertOnce(true)
                    .setAutoCancel(true)
                    .setContentIntent(pi);
            if (Build.VERSION.SDK_INT >= 26) {
                b.setBadgeIconType(Notification.BADGE_ICON_SMALL);
            }
            nm.notify(BADGE_NOTIF_ID, b.build());
        } catch (Exception ignored) { }
    }

    /** Affiche l'application par-dessus l'écran verrouillé (appel entrant). */
    private void setShowOnLock(final boolean on) {
        final Activity a = activity;
        if (a == null) return;
        a.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    if (Build.VERSION.SDK_INT >= 27) {
                        a.setShowWhenLocked(on);
                        a.setTurnScreenOn(on);
                    } else {
                        int f = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON;
                        if (on) a.getWindow().addFlags(f); else a.getWindow().clearFlags(f);
                    }
                } catch (Exception ignored) { }
            }
        });
    }

    private boolean micGranted() {
        if (Build.VERSION.SDK_INT < 23) return true;
        return context.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED;
    }

    private void releaseRecorder() {
        if (recorder != null) {
            try { recorder.release(); } catch (Exception ignored) { }
            recorder = null;
        }
    }

    private void releasePlayer() {
        if (player != null) {
            try { player.stop(); } catch (Exception ignored) { }
            try { player.release(); } catch (Exception ignored) { }
            player = null;
        }
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "isOnline": {
                result.success(isOnline());
                break;
            }
            case "watchNet": {
                watchNet();
                result.success(isOnline());
                break;
            }
            case "abis": {
                java.util.ArrayList<String> l = new java.util.ArrayList<>();
                if (Build.VERSION.SDK_INT >= 21) {
                    for (String a : Build.SUPPORTED_ABIS) l.add(a);
                }
                result.success(l);
                break;
            }
            case "hasMic": {
                result.success(micGranted());
                break;
            }
            case "askMic": {
                if (micGranted()) {
                    result.success(true);
                } else {
                    if (activity != null && Build.VERSION.SDK_INT >= 23) {
                        activity.requestPermissions(
                                new String[]{Manifest.permission.RECORD_AUDIO}, 7311);
                    }
                    result.success(false);
                }
                break;
            }
            case "start": {
                String path = call.argument("path");
                releaseRecorder();
                releasePlayer();
                try {
                    MediaRecorder r = new MediaRecorder();
                    r.setAudioSource(MediaRecorder.AudioSource.MIC);
                    r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
                    r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
                    r.setAudioEncodingBitRate(48000);
                    r.setAudioSamplingRate(22050);
                    r.setAudioChannels(1);
                    r.setOutputFile(path);
                    r.prepare();
                    r.start();
                    recorder = r;
                    result.success(true);
                } catch (Exception e) {
                    releaseRecorder();
                    result.error("REC", String.valueOf(e.getMessage()), null);
                }
                break;
            }
            case "stop": {
                boolean ok = recorder != null;
                if (recorder != null) {
                    try { recorder.stop(); } catch (Exception e) { ok = false; }
                }
                releaseRecorder();
                result.success(ok);
                break;
            }
            case "play": {
                String path = call.argument("path");
                releasePlayer();
                try {
                    final MediaPlayer p = new MediaPlayer();
                    p.setDataSource(path);
                    p.setOnCompletionListener(new MediaPlayer.OnCompletionListener() {
                        @Override
                        public void onCompletion(MediaPlayer mp) {
                            if (player == p) releasePlayer();
                            channel.invokeMethod("done", null);
                        }
                    });
                    p.prepare();
                    int duration = p.getDuration();
                    p.start();
                    player = p;
                    result.success(duration);
                } catch (Exception e) {
                    releasePlayer();
                    result.error("PLAY", String.valueOf(e.getMessage()), null);
                }
                break;
            }
            case "stopPlay": {
                releasePlayer();
                result.success(null);
                break;
            }
            case "ring": {
                stopRing();
                try {
                    ringtone = RingtoneManager.getRingtone(context,
                            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE));
                    if (ringtone != null) {
                        if (Build.VERSION.SDK_INT >= 28) ringtone.setLooping(true);
                        ringtone.play();
                    }
                } catch (Exception ignored) { }
                try {
                    vibrator = (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
                    if (vibrator != null) vibrator.vibrate(new long[]{0, 800, 800}, 0);
                } catch (Exception ignored) { }
                result.success(null);
                break;
            }
            case "stopRing": {
                stopRing();
                IncomingCall.dismiss(context);
                result.success(null);
                break;
            }
            case "position": {
                java.util.HashMap<String, Integer> m = new java.util.HashMap<>();
                int pos = 0, dur = 0;
                if (player != null) {
                    try { pos = player.getCurrentPosition(); dur = player.getDuration(); }
                    catch (Exception ignored) { }
                }
                m.put("position", pos);
                m.put("duration", dur);
                result.success(m);
                break;
            }
            case "openSettings": {
                try {
                    Intent i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:" + context.getPackageName()));
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    context.startActivity(i);
                } catch (Exception ignored) { }
                result.success(null);
                break;
            }
            case "showIncomingCall": {
                showIncomingCall((String) call.argument("callId"),
                        (String) call.argument("title"), (String) call.argument("body"));
                result.success(null);
                break;
            }
            case "cancelIncomingCall": {
                IncomingCall.dismiss(context);
                result.success(null);
                break;
            }
            case "takeAnswer": {
                result.success(IncomingCall.takeAnswer(context));
                break;
            }
            case "callChecks": {
                java.util.HashMap<String, Boolean> m = new java.util.HashMap<>();
                boolean notif = true;
                try {
                    NotificationManager nm = (NotificationManager)
                            context.getSystemService(Context.NOTIFICATION_SERVICE);
                    if (nm != null && Build.VERSION.SDK_INT >= 24) notif = nm.areNotificationsEnabled();
                } catch (Exception ignored) { }
                m.put("notifications", notif);
                m.put("fullScreen", IncomingCall.fullScreenAllowed(context));
                m.put("overlay", IncomingCall.overlayAllowed(context));
                boolean battery = true;
                try {
                    android.os.PowerManager pm = (android.os.PowerManager)
                            context.getSystemService(Context.POWER_SERVICE);
                    if (pm != null && Build.VERSION.SDK_INT >= 23)
                        battery = pm.isIgnoringBatteryOptimizations(context.getPackageName());
                } catch (Exception ignored) { }
                m.put("battery", battery);
                result.success(m);
                break;
            }
            case "openCallSetting": {
                String which = call.argument("which");
                Uri pkg = Uri.parse("package:" + context.getPackageName());
                Intent i;
                if ("overlay".equals(which) && Build.VERSION.SDK_INT >= 23) {
                    i = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkg);
                } else if ("fullScreen".equals(which) && Build.VERSION.SDK_INT >= 34) {
                    i = new Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg);
                } else if ("battery".equals(which) && Build.VERSION.SDK_INT >= 23) {
                    i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg);
                } else if (Build.VERSION.SDK_INT >= 26) {
                    i = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, context.getPackageName());
                } else {
                    i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg);
                }
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                try {
                    context.startActivity(i);
                } catch (Exception e) {
                    try {
                        context.startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                    } catch (Exception ignored) { }
                }
                result.success(null);
                break;
            }
            case "testIncomingCall": {
                // Test local : sonne dans 8 s (le temps de verrouiller l'écran).
                final Context app = context;
                new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
                    @Override public void run() {
                        IncomingCall.show(app, "test-" + System.currentTimeMillis(), "Test Aïcha Services");
                    }
                }, 8000);
                result.success(null);
                break;
            }
            case "ringback": {
                // « Tuut… tuut… » : ça sonne chez la personne appelée.
                stopTone();
                try {
                    tone = new ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80);
                    tone.startTone(ToneGenerator.TONE_SUP_RINGTONE);
                } catch (Exception ignored) { tone = null; }
                result.success(null);
                break;
            }
            case "busyTone": {
                stopTone();
                try {
                    tone = new ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80);
                    tone.startTone(ToneGenerator.TONE_SUP_BUSY, 2500);
                } catch (Exception ignored) { tone = null; }
                result.success(null);
                break;
            }
            case "stopTone": {
                stopTone();
                result.success(null);
                break;
            }
            case "setBadge": {
                Integer n = call.argument("count");
                setBadge(n == null ? 0 : n, (String) call.argument("text"));
                result.success(null);
                break;
            }
            case "showOnLock": {
                Boolean on = call.argument("on");
                setShowOnLock(on != null && on);
                result.success(null);
                break;
            }
            default:
                result.notImplemented();
        }
    }
}
