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
