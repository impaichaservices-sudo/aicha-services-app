/// 12500 -> "12 500 FCFA"
String fcfa(int amount) {
  final s = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${amount < 0 ? '-' : ''}$buf FCFA';
}

String shortDate(DateTime? d) {
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Numéro malien -> lien WhatsApp (https://wa.me/223XXXXXXXX)
Uri whatsappUri(String phone, [String text = '']) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.length == 8) digits = '223$digits';
  return Uri.parse(
      'https://wa.me/$digits${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');
}

/// "14:05" aujourd'hui, sinon "12/11 14:05".
String timeLabel(DateTime? d) {
  if (d == null) return 'envoi…';
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final hm = '${two(d.hour)}:${two(d.minute)}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return hm;
  return '${two(d.day)}/${two(d.month)} $hm';
}

/// Salutation selon l'heure : Bonjour (5 h – 12 h), Bon après-midi
/// (12 h – 18 h), Bonsoir (18 h – 5 h).
String greeting([DateTime? at]) {
  final h = (at ?? DateTime.now()).hour;
  if (h >= 5 && h < 12) return 'Bonjour';
  if (h >= 12 && h < 18) return 'Bon après-midi';
  return 'Bonsoir';
}

/// Prénom (premier mot du nom), pour saluer : « Bonjour Baba ».
String firstName(String name) {
  final n = name.trim();
  if (n.isEmpty) return '';
  return n.split(RegExp(r'\s+')).first;
}

/// « Bonjour Baba » (ou seulement « Bonjour » si le nom est inconnu).
String greetUser(String name) {
  final f = firstName(name);
  return f.isEmpty ? greeting() : '${greeting()} $f';
}

/// Message d'erreur compréhensible (au lieu du texte technique).
String friendlyError(Object? e) {
  final t = '$e'.toLowerCase();
  if (t.contains('permission-denied') || t.contains('permission_denied')) {
    return 'Action non autorisée pour votre compte.';
  }
  if (t.contains('unavailable') || t.contains('network') || t.contains('socket') ||
      t.contains('timeout') || t.contains('deadline')) {
    return 'Pas de connexion internet. Réessayez dans un instant.';
  }
  if (t.contains('failed-precondition') || t.contains('index')) {
    return 'Liste en préparation, réessayez dans quelques minutes.';
  }
  if (t.contains('not-found')) return 'Élément introuvable (peut-être supprimé).';
  if (t.contains('15 mo') || t.contains('trop lourd')) return 'Fichier trop lourd (15 Mo maximum).';
  if (t.contains('exception: ')) {
    return '$e'.replaceFirst(RegExp(r'^.*?Exception: '), '');
  }
  return 'Une erreur est survenue. Réessayez.';
}
