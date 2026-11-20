package ml.aichaservices.media;

import android.app.Activity;
import android.app.KeyguardManager;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.lang.ref.WeakReference;

/** Écran d'appel entrant plein écran (même écran verrouillé). */
public class IncomingCallActivity extends Activity {
    private String callId = "";
    private String name = "";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        }
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        IncomingCall.screen = new WeakReference<Activity>(this);
        handle(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handle(intent);
    }

    private void handle(Intent i) {
        if (i != null) {
            String c = i.getStringExtra("callId");
            String n = i.getStringExtra("name");
            if (c != null) callId = c;
            if (n != null) name = n;
        }
        if (IncomingCall.currentId == null) {
            if (callId.isEmpty()) { finish(); return; }
            IncomingCall.currentId = callId; // application relancée par Android
            IncomingCall.currentAt = System.currentTimeMillis();
        }
        if (i != null && IncomingCall.ACTION_ANSWER.equals(i.getAction())) {
            answer();
            return;
        }
        setContentView(buildUi());
    }

    private int dp(float v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }

    private TextView text(String s, float sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        t.setGravity(Gravity.CENTER);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }

    private TextView button(String label, int color, View.OnClickListener l) {
        TextView b = text(label, 18, Color.WHITE, true);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(color);
        bg.setCornerRadius(dp(40));
        b.setBackground(bg);
        b.setPadding(dp(8), dp(18), dp(8), dp(18));
        b.setOnClickListener(l);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        lp.setMargins(dp(12), 0, dp(12), 0);
        b.setLayoutParams(lp);
        return b;
    }

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setBackgroundColor(Color.parseColor("#0B3D0B"));
        root.setPadding(dp(16), dp(80), dp(16), dp(60));

        root.addView(text("Aïcha Services", 16, Color.parseColor("#A5D6A7"), true));
        TextView avatar = text(name.isEmpty() ? "📞" : name.substring(0, 1).toUpperCase(),
                44, Color.WHITE, true);
        GradientDrawable circle = new GradientDrawable();
        circle.setShape(GradientDrawable.OVAL);
        circle.setColor(Color.parseColor("#1F8A1F"));
        avatar.setBackground(circle);
        LinearLayout.LayoutParams alp = new LinearLayout.LayoutParams(dp(120), dp(120));
        alp.setMargins(0, dp(48), 0, dp(24));
        avatar.setLayoutParams(alp);
        root.addView(avatar);
        root.addView(text(name.isEmpty() ? "Appel entrant" : name, 30, Color.WHITE, true));
        TextView sub = text(callId.startsWith("room:") ? "Réunion de l'équipe…" : "Appel vocal par internet…",
                17, Color.parseColor("#C8E6C9"), false);
        sub.setPadding(0, dp(10), 0, 0);
        root.addView(sub);

        View space = new View(this);
        root.addView(space, new LinearLayout.LayoutParams(1, 0, 1f));

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.addView(button("✕  Refuser", Color.parseColor("#D32F2F"), new View.OnClickListener() {
            @Override public void onClick(View v) { IncomingCall.dismiss(IncomingCallActivity.this); }
        }));
        row.addView(button("📞  Répondre", Color.parseColor("#2E7D32"), new View.OnClickListener() {
            @Override public void onClick(View v) { answer(); }
        }));
        root.addView(row, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        return root;
    }

    /** Répondre : l'application s'ouvre et décroche automatiquement. */
    private void answer() {
        IncomingCall.setAnswer(this, callId);
        IncomingCall.currentId = null;
        try {
            android.app.NotificationManager nm = (android.app.NotificationManager)
                    getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.cancel(IncomingCall.NOTIF_ID); // arrête la sonnerie
        } catch (Exception ignored) { }
        KeyguardManager km = (KeyguardManager) getSystemService(KEYGUARD_SERVICE);
        if (Build.VERSION.SDK_INT >= 26 && km != null && km.isKeyguardLocked()) {
            km.requestDismissKeyguard(this, new KeyguardManager.KeyguardDismissCallback() {
                @Override public void onDismissSucceeded() { openApp(); }
                @Override public void onDismissCancelled() { openApp(); }
                @Override public void onDismissError() { openApp(); }
            });
        } else {
            openApp();
        }
    }

    private void openApp() {
        try {
            Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                launch.putExtra("incoming_call", callId);
                startActivity(launch);
            }
        } catch (Exception ignored) { }
        finish();
    }

    @Override
    protected void onDestroy() {
        Activity a = IncomingCall.screen == null ? null : IncomingCall.screen.get();
        if (a == this) IncomingCall.screen = null;
        super.onDestroy();
    }
}
