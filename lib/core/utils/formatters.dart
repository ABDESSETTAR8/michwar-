import 'package:intl/intl.dart';

/// Currency / number / date formatting helpers for the Algerian Dinar (DZD).
class Formatters {
  Formatters._();

  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'fr_DZ',
    symbol: 'DA',
    decimalDigits: 2,
  );

  static String currency(num value) => _currency.format(value);

  static String distanceKm(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  static String durationMin(double minutes) {
    if (minutes < 1) return '< 1 min';
    if (minutes < 60) return '${minutes.round()} min';
    final hours = (minutes / 60).floor();
    final rem = (minutes % 60).round();
    return '${hours}h ${rem}m';
  }

  static String dateTime(DateTime dt) =>
      DateFormat('dd MMM yyyy, HH:mm').format(dt);

  static String time(DateTime dt) => DateFormat('HH:mm').format(dt);

  static String maskedPhone(String phone) {
    if (phone.length < 4) return phone;
    return '${phone.substring(0, phone.length - 4)}****';
  }
}
