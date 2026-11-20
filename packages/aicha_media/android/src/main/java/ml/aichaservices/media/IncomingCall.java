package ml.aichaservices.media;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import java.lang.ref.WeakReference;
import java.util.ArrayDeque;

/**
 * Appel entrant affiché par Android lui-même, SANS attendre le démarrage de
 * l'application : sonnerie continue, écran d'appel en plein écran (écran
 * éteint ou verrouillé ; aussi téléphone déverrouillé si la « superposition »
 * est autorisée).
 */
final class IncomingCall {
    static final int NOTIF_ID = 7312;
    static final String CHANNEL = "aicha_calls_v2";
    static final String OLD_CHANNEL = "aicha_calls";
    static final String ACTION_ANSWER = "ml.aichaservices.media.ANSWER";
    static final String ACTION_DECLINE = "ml.aichaservices.media.DECLINE";
    static final long RING_MS = 45000;

    static String currentId = null;
    static String currentName = "";
    static long currentAt = 0;
    static WeakReference<Activity> screen = null;
    private static final ArrayDeque<String> endedIds = new ArrayDeque<>();
    private static final Handler main = new Handler(Looper.getMainLooper());

    private IncomingCall() { }

    /** L'application est-elle à l'écran ? (elle gère alors l'appel elle-même) */
    static boolean appInForeground() {
        try {
            ActivityManager.RunningAppProcessInfo info = new ActivityManager.RunningAppProcessInfo();
            ActivityManager.getMyMemoryState(info);
            Activity a = screen == null ? null : screen.get();
            return info.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
                    && a == null;
        } catch (Exception e) {
            return false;
        }
    }

    static boolean overlayAllowed(Context ctx) {
        return Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(ctx);
    }

    static boolean fullScreenAllowed(Context ctx) {
        if (Build.VERSION.SDK_INT < 34) return true;
        NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        return nm == null || nm.canUseFullScreenIntent();
    }

    private static void ensureChannel(NotificationManager nm) {
        if (Build.VERSION.SDK_INT < 26) return;
        try { nm.deleteNotificationChannel(OLD_CHANNEL); } catch (Exception ignored) { }
        if (nm.getNotificationChannel(CHANNEL) != null) return;
        NotificationChannel ch = new NotificationChannel(CHANNEL,
                "Appels entrants", NotificationManager.IMPORTANCE_HIGH);
        ch.setDescription("Sonnerie des appels Aïcha Services");
        Uri ring = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
        ch.setSound(ring, new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build());
        ch.enableVibration(true);
        ch.setVibrationPattern(new long[]{0, 1000, 1000, 1000, 1000});
        ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        ch.setShowBadge(true);
        nm.createNotificationChannel(ch);
    }

    private static int piFlags() {
        int f = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) f |= PendingIntent.FLAG_IMMUTABLE;
        return f;
    }

    static Intent screenIntent(Context ctx, String callId, String name, String action) {
        Intent i = new Intent(ctx, IncomingCallActivity.class);
        if (action != null) i.setAction(action);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_USER_ACTION);
        i.putExtra("callId", callId);
        i.putExtra("name", name);
        return i;
    }

    /** Fait sonner le téléphone et affiche l'écran d'appel. */
    static synchronized void show(Context ctx, String callId, String name) {
        if (callId == null) callId = "";
        if (name == null) name = "";
        long now = System.currentTimeMillis();
        if (endedIds.contains(callId)) return;           // déjà terminé
        if (callId.equals(currentId) && now - currentAt < RING_MS) return; // déjà affiché
        currentId = callId;
        currentName = name;
        currentAt = now;
        try {
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            ensureChannel(nm);
            String title = name.isEmpty() ? "Appel entrant" : name;
            PendingIntent full = PendingIntent.getActivity(ctx, 7320,
                    screenIntent(ctx, callId, name, null), piFlags());
            PendingIntent answer = PendingIntent.getActivity(ctx, 7321,
                    screenIntent(ctx, callId, name, ACTION_ANSWER), piFlags());
            Intent dec = new Intent(ctx, CallActionReceiver.class).setAction(ACTION_DECLINE);
            PendingIntent decline = PendingIntent.getBroadcast(ctx, 7322, dec, piFlags());

            Notification.Builder b = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(ctx, CHANNEL)
                    : new Notification.Builder(ctx);
            int icon = ctx.getApplicationInfo().icon;
            b.setSmallIcon(icon == 0 ? android.R.drawable.sym_call_incoming : icon)
                    .setContentTitle("📞 " + title)
                    .setContentText("Appel Aïcha Services • touchez pour répondre")
                    .setCategory(Notification.CATEGORY_CALL)
                    .setPriority(Notification.PRIORITY_MAX)
                    .setVisibility(Notification.VISIBILITY_PUBLIC)
                    .setOngoing(true)
                    .setAutoCancel(false)
                    .setContentIntent(full)
                    .setFullScreenIntent(full, true)
                    .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Refuser", decline)
                    .addAction(android.R.drawable.sym_action_call, "Répondre", answer);
            if (Build.VERSION.SDK_INT < 26) {
                b.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                        AudioManager.STREAM_RING)
                        .setVibrate(new long[]{0, 1000, 1000, 1000, 1000});
            } else {
                b.setTimeoutAfter(RING_MS);
            }
            Notification n = b.build();
            n.flags |= Notification.FLAG_INSISTENT; // la sonnerie se répète
            nm.notify(NOTIF_ID, n);

            // Téléphone déverrouillé : Android n'affiche qu'un bandeau, sauf si
            // la superposition est autorisée → on ouvre directement l'écran.
            if (overlayAllowed(ctx)) {
                try { ctx.startActivity(screenIntent(ctx, callId, name, null)); }
                catch (Exception ignored) { }
            }
            final String id = callId;
            final Context app = ctx.getApplicationContext();
            main.postDelayed(new Runnable() {
                @Override public void run() {
                    if (id.equals(currentId)) dismiss(app);
                }
            }, RING_MS);
        } catch (Exception ignored) { }
    }

    /** Arrête la sonnerie et ferme l'écran d'appel. */
    static synchronized void dismiss(Context ctx) {
        currentId = null;
        try {
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) nm.cancel(NOTIF_ID);
        } catch (Exception ignored) { }
        final Activity a = screen == null ? null : screen.get();
        if (a != null) {
            main.post(new Runnable() {
                @Override public void run() { a.finish(); }
            });
        }
    }

    /** L'appel est terminé (décroché ailleurs, annulé…). */
    static synchronized void ended(Context ctx, String callId) {
        if (callId != null && !callId.isEmpty()) {
            endedIds.add(callId);
            while (endedIds.size() > 20) endedIds.poll();
        }
        if (currentId == null || callId == null || callId.equals(currentId)) dismiss(ctx);
    }

    // ---- « Répondre » touché : l'application décroche dès qu'elle s'ouvre ----
    private static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences("aicha_media", Context.MODE_PRIVATE);
    }

    static void setAnswer(Context ctx, String callId) {
        prefs(ctx).edit().putString("answer", callId == null ? "" : callId)
                .putLong("answerAt", System.currentTimeMillis()).apply();
    }

    static String takeAnswer(Context ctx) {
        SharedPreferences p = prefs(ctx);
        String id = p.getString("answer", "");
        long at = p.getLong("answerAt", 0);
        p.edit().remove("answer").remove("answerAt").apply();
        return System.currentTimeMillis() - at < 120000 ? id : "";
    }
}
