/// Form-field validators shared across Authentication and Profile screens.
class Validators {
  Validators._();

  /// Validates an Algerian mobile number entered without the country code,
  /// e.g. "551234567" (9 digits, starts with 5, 6, or 7).
  static String? algerianPhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final digits = value.trim().replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[567]\d{8}$').hasMatch(digits)) {
      return 'Enter a valid Algerian mobile number (e.g. 5XXXXXXXX)';
    }
    return null;
  }

  static String? otpCode(String? value, {int length = 6}) {
    if (value == null || value.trim().length != length) {
      return 'Enter the $length-digit code';
    }
    if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
      return 'Code must be numeric';
    }
    return null;
  }

  /// Validates an email address used as the PocketBase `users` login
  /// identity.
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final email = value.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Validates a password for sign-up. PocketBase's default `users`
  /// collection requires a minimum of 8 characters.
  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  /// Validates that [value] matches [original] (password confirmation).
  static String? Function(String?) confirmPassword(String original) {
    return (value) {
      if (value == null || value.isEmpty) {
        return 'Please confirm your password';
      }
      if (value != original) {
        return 'Passwords do not match';
      }
      return null;
    };
  }

  static String? required(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  static String? plateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Plate number is required';
    }
    if (value.trim().length < 4) {
      return 'Enter a valid plate number';
    }
    return null;
  }
}
