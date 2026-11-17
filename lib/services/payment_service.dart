import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

/// Paiement en ligne via CinetPay (Orange Money, Moov Money, carte).
/// La clé CinetPay reste sur le serveur (Cloud Function), jamais dans l'appli.
class PaymentService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'europe-west1');

  static String channelFor(String method) =>
      method == 'carte' ? 'CREDIT_CARD' : 'MOBILE_MONEY';

  static Future<void> pay({
    required List<String> orderIds,
    required String method,
  }) async {
    final res = await _fn.httpsCallable('initPayment').call({
      'orderIds': orderIds,
      'channel': channelFor(method),
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    final uri = Uri.parse(data['paymentUrl'] as String);
    var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!ok) throw Exception("Impossible d'ouvrir la page de paiement.");
  }

  static String message(Object e) {
    if (e is FirebaseFunctionsException) {
      return e.message ?? 'Erreur de paiement (${e.code}).';
    }
    return 'Erreur de paiement : $e';
  }
}
