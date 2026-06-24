/// Role assigned to a user. MICHWAR is a *unified* app — the same person
/// could in theory hold both roles, but `activeRole` decides which UI is
/// rendered for the current session.
enum UserRole { passenger, driver, admin }

UserRole userRoleFromString(String? value) {
  switch (value) {
    case 'driver':
      return UserRole.driver;
    case 'admin':
      return UserRole.admin;
    default:
      return UserRole.passenger;
  }
}

String userRoleToString(UserRole role) => role.name;

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final str = value.toString();
  if (str.isEmpty) return null;
  return DateTime.tryParse(str);
}

/// Maps to a record in the PocketBase `users` auth collection.
///
/// ```jsonc
/// users/{id} {
///   email: string,               // login identity (passwordAuth)
///   phoneNumber: string,          // plain profile field, no longer used for OTP
///   fullName: string,
///   role: "passenger" | "driver" | "admin",
///   roleSelected: boolean,         // false until Role Selection is completed
///   avatar: string | null,        // PocketBase file field (filename)
///   loyaltyPoints: number,
///   loyaltyTier: "standard" | "eco" | "premium",
///   totalRidesCompleted: number,
///   savedPlaces: { label, lat, lng, address? }[],
///   sosContacts: { name, phone }[],
///   fcmTokens: string[],          // unused without FCM, kept for future use
///   created, updated: ISO8601 string
/// }
/// ```
class UserModel {
  final String uid;
  final String phoneNumber;
  final String fullName;
  final String? email;
  final UserRole role;
  final bool roleSelected;
  final String? avatar;
  final LoyaltyInfo loyalty;
  final List<SavedPlace> savedPlaces;
  final List<SosContact> sosContacts;
  final List<String> fcmTokens;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserModel({
    required this.uid,
    required this.phoneNumber,
    required this.fullName,
    required this.role,
    this.roleSelected = false,
    this.email,
    this.avatar,
    this.loyalty = const LoyaltyInfo(),
    this.savedPlaces = const [],
    this.sosContacts = const [],
    this.fcmTokens = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      phoneNumber: map['phoneNumber'] as String? ?? '',
      fullName: map['fullName'] as String? ?? '',
      email: map['email'] as String?,
      role: userRoleFromString(map['role'] as String?),
      roleSelected: map['roleSelected'] as bool? ?? false,
      avatar: (map['avatar'] as String?)?.isEmpty ?? true
          ? null
          : map['avatar'] as String?,
      loyalty: LoyaltyInfo.fromMap(map),
      savedPlaces: ((map['savedPlaces'] as List<dynamic>?) ?? const [])
          .map((e) => SavedPlace.fromMap(e as Map<String, dynamic>))
          .toList(),
      sosContacts: ((map['sosContacts'] as List<dynamic>?) ?? const [])
          .map((e) => SosContact.fromMap(e as Map<String, dynamic>))
          .toList(),
      fcmTokens: ((map['fcmTokens'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      createdAt: _parseDate(map['created']),
      updatedAt: _parseDate(map['updated']),
    );
  }

  /// Reads a Firestore document snapshot. Firestore Timestamps are converted
  /// to ISO strings for compatibility with the shared [_parseDate] helper.
  factory UserModel.fromFirestore(String uid, Map<String, dynamic> map) {
    final normalized = Map<String, dynamic>.from(map);
    for (final key in ['createdAt', 'updatedAt']) {
      final v = normalized[key];
      if (v != null && v.runtimeType.toString().contains('Timestamp')) {
        // ignore: avoid_dynamic_calls
        normalized[key] = (v as dynamic).toDate().toIso8601String();
      }
    }
    // Firestore uses 'createdAt'/'updatedAt'; PB used 'created'/'updated'.
    normalized['created'] = normalized['createdAt'];
    normalized['updated'] = normalized['updatedAt'];
    return UserModel.fromMap(uid, normalized);
  }

  /// Body for `pb.collection('users').update(uid, body: ...)`. Only includes
  /// fields a user may self-edit — `role` / `loyalty*` / `totalRidesCompleted`
  /// are server-protected (see `pb_hooks/10_users.pb.js`).
  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      if (email != null) 'email': email,
      'savedPlaces': savedPlaces.map((e) => e.toMap()).toList(),
      'sosContacts': sosContacts.map((e) => e.toMap()).toList(),
      'fcmTokens': fcmTokens,
    };
  }

  UserModel copyWith({
    String? fullName,
    String? email,
    UserRole? role,
    bool? roleSelected,
    String? avatar,
    LoyaltyInfo? loyalty,
    List<SavedPlace>? savedPlaces,
    List<SosContact>? sosContacts,
    List<String>? fcmTokens,
  }) {
    return UserModel(
      uid: uid,
      phoneNumber: phoneNumber,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      roleSelected: roleSelected ?? this.roleSelected,
      avatar: avatar ?? this.avatar,
      loyalty: loyalty ?? this.loyalty,
      savedPlaces: savedPlaces ?? this.savedPlaces,
      sosContacts: sosContacts ?? this.sosContacts,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// "MICHWAR Points" gamification state (Section 5 / 3.A).
class LoyaltyInfo {
  final int points;
  final String tier; // standard | eco | premium
  final int totalRidesCompleted;

  const LoyaltyInfo({
    this.points = 0,
    this.tier = 'standard',
    this.totalRidesCompleted = 0,
  });

  /// Reads loyalty data from Firestore. Supports two storage layouts:
  ///   1. Nested: `loyalty: { points, tier, totalRides }` (seed script)
  ///   2. Flat: `loyaltyPoints`, `loyaltyTier`, `totalRidesCompleted` (signUp)
  factory LoyaltyInfo.fromMap(Map<String, dynamic> map) {
    final nested = map['loyalty'] as Map?;
    return LoyaltyInfo(
      points: ((nested?['points'] ?? map['loyaltyPoints']) as num?)?.toInt() ?? 0,
      tier: (nested?['tier'] ?? map['loyaltyTier']) as String? ?? 'standard',
      totalRidesCompleted:
          ((nested?['totalRides'] ?? nested?['totalRidesCompleted'] ?? map['totalRidesCompleted']) as num?)
              ?.toInt() ?? 0,
    );
  }
}

/// A saved location such as "Home" or "Work" used for predictive
/// destination suggestions.
class SavedPlace {
  final String label;
  final double lat;
  final double lng;
  final String? address;

  const SavedPlace({
    required this.label,
    required this.lat,
    required this.lng,
    this.address,
  });

  factory SavedPlace.fromMap(Map<String, dynamic> map) => SavedPlace(
        label: map['label'] as String? ?? '',
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
        address: map['address'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'label': label,
        'lat': lat,
        'lng': lng,
        'address': address,
      };
}

/// Emergency contact notified when the in-app SOS button is triggered.
class SosContact {
  final String name;
  final String phone;

  const SosContact({required this.name, required this.phone});

  factory SosContact.fromMap(Map<String, dynamic> map) => SosContact(
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};
}
