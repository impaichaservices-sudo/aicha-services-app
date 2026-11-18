package ml.aichaservices.media;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.media.AudioAttributes;
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
        try {
            NotificationManager nm = (NotificationManager)
                    context.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            Uri ring = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
            if (Build.VERSION.SDK_INT >= 26) {
                NotificationChannel ch = new NotificationChannel(CALL_CHANNEL,
                        "Appels", NotificationManager.IMPORTANCE_HIGH);
                ch.setDescription("Appels entrants Aïcha Services");
                ch.setSound(ring, new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build());
                ch.enableVibration(true);
                ch.setVibrationPattern(new long[]{0, 800, 800, 800, 800});
                ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
                nm.createNotificationChannel(ch);
            }
            Intent launch = context.getPackageManager()
                    .getLaunchIntentForPackage(context.getPackageName());
            if (launch == null) return;
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            launch.putExtra("incoming_call", callId == null ? "" : callId);
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
            PendingIntent pi = PendingIntent.getActivity(context, 7313, launch, flags);
            Notification.Builder b = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(context, CALL_CHANNEL)
                    : new Notification.Builder(context);
            int icon = context.getApplicationInfo().icon;
            b.setSmallIcon(icon == 0 ? android.R.drawable.sym_call_incoming : icon)
                    .setContentTitle(title == null ? "Appel entrant" : title)
                    .setContentText(body == null ? "Aïcha Services" : body)
                    .setCategory(Notification.CATEGORY_CALL)
                    .setPriority(Notification.PRIORITY_MAX)
                    .setVisibility(Notification.VISIBILITY_PUBLIC)
                    .setAutoCancel(true)
                    .setOngoing(true)
                    .setContentIntent(pi)
                    .setFullScreenIntent(pi, true)
                    .addAction(android.R.drawable.sym_action_call, "Répondre", pi);
            if (Build.VERSION.SDK_INT < 26) {
                b.setSound(ring).setVibrate(new long[]{0, 800, 800, 800, 800});
            } else {
                b.setTimeoutAfter(45000);
            }
            nm.notify(CALL_NOTIF_ID, b.build());
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
                try {
                    NotificationManager nm = (NotificationManager)
                            context.getSystemService(Context.NOTIFICATION_SERVICE);
                    if (nm != null) nm.cancel(CALL_NOTIF_ID);
                } catch (Exception ignored) { }
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
