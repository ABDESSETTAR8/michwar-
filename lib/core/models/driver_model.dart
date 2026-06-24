/// Driver verification / activation status.
enum DriverVerificationStatus { pending, underReview, approved, rejected }

DriverVerificationStatus driverStatusFromString(String? value) {
  switch (value) {
    case 'under_review':
      return DriverVerificationStatus.underReview;
    case 'approved':
      return DriverVerificationStatus.approved;
    case 'rejected':
      return DriverVerificationStatus.rejected;
    default:
      return DriverVerificationStatus.pending;
  }
}

String driverStatusToString(DriverVerificationStatus status) {
  switch (status) {
    case DriverVerificationStatus.underReview:
      return 'under_review';
    case DriverVerificationStatus.approved:
      return 'approved';
    case DriverVerificationStatus.rejected:
      return 'rejected';
    case DriverVerificationStatus.pending:
      return 'pending';
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final str = value.toString();
  if (str.isEmpty) return null;
  return DateTime.tryParse(str);
}

/// Maps to a record in the PocketBase `drivers` collection
/// (`pocketbase/pb_migrations/1700000002_drivers.js`). `id` is the
/// `drivers` record's own PocketBase id; `userId` is the `user` relation
/// field pointing at the corresponding `users` record.
class DriverModel {
  final String id;
  final String userId;
  final VehicleInfo vehicle;
  final DriverVerificationStatus verificationStatus;
  final List<String> documents;
  final Map<String, dynamic> documentsMeta;
  final String commissionTier; // tier1 | tier2
  final double commissionRate; // company share of base fare
  final double driverShareRate; // driver share of base fare
  final int ridesCompleted;
  final double ratingAverage;
  final int ratingCount;
  final bool isOnline;
  final bool isOnTrip;
  final HeadingHomeSettings headingHome;
  final DriverLocation? location;
  final double walletBalance;

  const DriverModel({
    required this.id,
    required this.userId,
    required this.vehicle,
    this.verificationStatus = DriverVerificationStatus.pending,
    this.documents = const [],
    this.documentsMeta = const {},
    this.commissionTier = 'tier1',
    this.commissionRate = 0.15,
    this.driverShareRate = 0.85,
    this.ridesCompleted = 0,
    this.ratingAverage = 5.0,
    this.ratingCount = 0,
    this.isOnline = false,
    this.isOnTrip = false,
    this.headingHome = const HeadingHomeSettings(),
    this.location,
    this.walletBalance = 0,
  });

  bool get isElite => commissionTier == 'tier2';

  /// Whether the driver's wallet balance is healthy enough to receive new
  /// ride requests (mirrors the server-side check in
  /// `pocketbase/pb_hooks/12_rides.pb.js`).
  bool get canReceiveRides =>
      verificationStatus == DriverVerificationStatus.approved &&
      walletBalance > 200.0; // AppConstants.walletLowBalanceThresholdDzd

  factory DriverModel.fromFirestore(String id, Map<String, dynamic> map) {
    // Firestore uses 'userId' field; normalise for fromMap.
    final normalized = Map<String, dynamic>.from(map);
    normalized['user'] ??= normalized['userId'];
    return DriverModel.fromMap(id, normalized);
  }

  factory DriverModel.fromMap(String id, Map<String, dynamic> map) {
    return DriverModel(
      id: id,
      userId: map['user'] as String? ?? '',
      vehicle: VehicleInfo.fromMap(map),
      verificationStatus:
          driverStatusFromString(map['verificationStatus'] as String?),
      documents: ((map['documents'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      documentsMeta:
          (map['documentsMeta'] as Map<String, dynamic>?) ?? const {},
      commissionTier: map['commissionTier'] as String? ?? 'tier1',
      commissionRate: (map['commissionRate'] as num?)?.toDouble() ?? 0.15,
      driverShareRate: (map['driverShareRate'] as num?)?.toDouble() ?? 0.85,
      ridesCompleted: (map['ridesCompleted'] as num?)?.toInt() ?? 0,
      ratingAverage: (map['ratingAverage'] as num?)?.toDouble() ?? 5.0,
      ratingCount: (map['ratingCount'] as num?)?.toInt() ?? 0,
      isOnline: map['isOnline'] as bool? ?? false,
      isOnTrip: map['isOnTrip'] as bool? ?? false,
      headingHome: HeadingHomeSettings.fromMap(map),
      location: map['locationGeohash'] == null ||
              (map['locationGeohash'] as String).isEmpty
          ? null
          : DriverLocation.fromMap(map),
      walletBalance: (map['walletBalance'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Body for `pb.collection('drivers').update(id, body: ...)`. Only
  /// includes fields a driver may self-edit directly — financial /
  /// performance / verification fields are reverted server-side
  /// (`pb_hooks/11_drivers.pb.js`) if present here.
  Map<String, dynamic> toMap() {
    return {
      ...vehicle.toMap(),
      'documents': documents,
      'documentsMeta': documentsMeta,
      'isOnline': isOnline,
      ...headingHome.toMap(),
      if (location != null) ...location!.toMap(),
    };
  }
}

class VehicleInfo {
  final String make;
  final String model;
  final String plate;
  final String color;
  final String category; // standard | eco | premium

  const VehicleInfo({
    this.make = '',
    this.model = '',
    this.plate = '',
    this.color = '',
    this.category = 'standard',
  });

  factory VehicleInfo.fromMap(Map<String, dynamic> map) => VehicleInfo(
        make: map['vehicleMake'] as String? ?? '',
        model: map['vehicleModel'] as String? ?? '',
        plate: map['vehiclePlate'] as String? ?? '',
        color: map['vehicleColor'] as String? ?? '',
        category: map['vehicleCategory'] as String? ?? 'standard',
      );

  Map<String, dynamic> toMap() => {
        'vehicleMake': make,
        'vehicleModel': model,
        'vehiclePlate': plate,
        'vehicleColor': color,
        'vehicleCategory': category,
      };
}

/// "Heading Home" toggle (Smart Driver Tools).
class HeadingHomeSettings {
  final bool enabled;
  final double? destinationLat;
  final double? destinationLng;

  /// Ride requests whose drop-off bearing from the driver deviates from
  /// the driver's own bearing-to-home by more than this tolerance are
  /// filtered out.
  final double bearingToleranceDeg;

  const HeadingHomeSettings({
    this.enabled = false,
    this.destinationLat,
    this.destinationLng,
    this.bearingToleranceDeg = 30,
  });

  factory HeadingHomeSettings.fromMap(Map<String, dynamic> map) =>
      HeadingHomeSettings(
        enabled: map['headingHomeEnabled'] as bool? ?? false,
        destinationLat: (map['headingHomeDestLat'] as num?)?.toDouble(),
        destinationLng: (map['headingHomeDestLng'] as num?)?.toDouble(),
        bearingToleranceDeg:
            (map['headingHomeBearingTolerance'] as num?)?.toDouble() ?? 30,
      );

  Map<String, dynamic> toMap() => {
        'headingHomeEnabled': enabled,
        'headingHomeDestLat': destinationLat,
        'headingHomeDestLng': destinationLng,
        'headingHomeBearingTolerance': bearingToleranceDeg,
      };
}

/// Real-time driver position, stored with a Geohash for proximity queries.
class DriverLocation {
  final double lat;
  final double lng;
  final String geohash;
  final double heading;
  final double speed; // m/s
  final DateTime? updatedAt;

  const DriverLocation({
    required this.lat,
    required this.lng,
    required this.geohash,
    this.heading = 0,
    this.speed = 0,
    this.updatedAt,
  });

  factory DriverLocation.fromMap(Map<String, dynamic> map) => DriverLocation(
        lat: (map['locationLat'] as num?)?.toDouble() ?? 0,
        lng: (map['locationLng'] as num?)?.toDouble() ?? 0,
        geohash: map['locationGeohash'] as String? ?? '',
        heading: (map['locationHeading'] as num?)?.toDouble() ?? 0,
        speed: (map['locationSpeed'] as num?)?.toDouble() ?? 0,
        updatedAt: _parseDate(map['locationUpdatedAt']),
      );

  Map<String, dynamic> toMap() => {
        'locationLat': lat,
        'locationLng': lng,
        'locationGeohash': geohash,
        'locationHeading': heading,
        'locationSpeed': speed,
        'locationUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      };
}
