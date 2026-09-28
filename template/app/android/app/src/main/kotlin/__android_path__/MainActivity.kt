package {= android_id =}

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Abre um link num app específico (o do Discord, para autorizar a entrada), sem depender de
        // o app estar marcado para abrir os links dele: com o pacote no intent, o Android entrega
        // direto. `false` quando o app não está instalado (lib/platform/platform_native.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "{= name =}/apps").setMethodCallHandler { call, result ->
            if (call.method != "openIn") return@setMethodCallHandler result.notImplemented()
            val url = call.argument<String>("url")
            val pkg = call.argument<String>("package")
            if (url == null || pkg == null) return@setMethodCallHandler result.success(false)
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                result.success(true)
            } catch (e: ActivityNotFoundException) {
                result.success(false)
            }
        }
    }
}
