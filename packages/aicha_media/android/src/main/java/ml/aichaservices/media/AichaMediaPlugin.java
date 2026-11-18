package ml.aichaservices.media;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.MediaPlayer;
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
            default:
                result.notImplemented();
        }
    }
}
