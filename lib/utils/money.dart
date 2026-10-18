/// Money formatting using integer math only — never doubles for money.
String formatRupees(int paise) {
  final rupees = paise ~/ 100;
  final remaining = paise % 100;
  return '₹$rupees.${remaining.toString().padLeft(2, '0')}';
}
