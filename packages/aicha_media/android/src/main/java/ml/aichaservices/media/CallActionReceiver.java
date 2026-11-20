package ml.aichaservices.media;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Bouton « Refuser » de la notification d'appel. */
public class CallActionReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context ctx, Intent intent) {
        IncomingCall.dismiss(ctx);
    }
}
