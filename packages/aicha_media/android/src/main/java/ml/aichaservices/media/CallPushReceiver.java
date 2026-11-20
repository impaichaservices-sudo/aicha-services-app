package ml.aichaservices.media;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Reçoit directement les messages Firebase (même application fermée) :
 * l'appel sonne immédiatement, sans attendre le démarrage de Flutter.
 */
public class CallPushReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context ctx, Intent intent) {
        try {
            if (intent == null) return;
            String type = intent.getStringExtra("type");
            if (type == null) return;
            String callId = intent.getStringExtra("callId");
            if ("call_ended".equals(type)) {
                IncomingCall.ended(ctx, callId);
            } else if ("incoming_call".equals(type)) {
                // Application ouverte à l'écran : elle affiche l'appel elle-même.
                if (IncomingCall.appInForeground()) return;
                IncomingCall.show(ctx, callId, intent.getStringExtra("callerName"));
            }
        } catch (Exception ignored) { }
    }
}
