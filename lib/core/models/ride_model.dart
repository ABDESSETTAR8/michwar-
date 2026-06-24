/// Full lifecycle of a ride. Persisted as `rides/{rideId}.status`.
enum RideStatus {
  searching, // passenger requested, matching engine looking for a driver
  accepted, // a driver accepted, en route to pickup
  arrived, // driver arrived at pickup point
  ongoing, // trip in progress
  completed, // trip finished, fare finalized server-side
  cancelledByPassenger,
  cancelledByDriver,
  noDriversFound,
}

RideStatus rideStatusFromString(String? value) {
  switch (value) {
    case 'accepted':
      return RideStatus.accepted;
    case 'arrived':
      return RideStatus.arrived;
    case 'ongoing':
      return RideStatus.ongoing;
    case 'completed':
      return RideStatus.completed;
    case 'cancelled_by_passenger':
      return RideStatus.cancelledByPassenger;
    case 'cancelled_by_driver':
      return RideStatus.cancelledByDriver;
    case 'no_drivers_found':
      return RideStatus.noDriversFound;
    default:
      return RideStatus.searching;
  }
}

String rideStatusToString(RideStatus status) {
  switch (status) {
    case RideStatus.accepted:
      return 'accepted';
    case RideStatus.arrived:
      return 'arrived';
    case RideStatus.ongoing:
      return 'ongoing';
    case RideStatus.completed:
      return 'completed';
    case RideStatus.cancelledByPassenger:
      return 'cancelled_by_passenger';
    case RideStatus.cancelledByDriver:
      return 'cancelled_by_driver';
    case RideStatus.noDriversFound:
      return 'no_drivers_found';
    case RideStatus.searching:
      return 'searching';
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final str = value.toString();
  if (str.isEmpty) return null;
  return DateTime.tryParse(str);
}

/// A geographic point with its Geohash, used for both pickup/drop-off
/// locations and for driver-matching queries. Stored as a JSON blob inside
/// the `rides.pickup` / `rides.dropoff` fields — shape is unchanged from
/// the Firebase version.
class GeoPoint2 {
  final double lat;
  final double lng;
  final String? address;
  final String? geohash;

  const GeoPoint2({required this.lat, required this.lng, this.address, this.geohash});

  factory GeoPoint2.fromMap(Map<String, dynamic> map) => GeoPoint2(
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
        address: map['address'] as String?,
        geohash: map['geohash'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        if (address != null) 'address': address,
        if (geohash != null) 'geohash': geohash,
      };
}

/// Maps to a record in the PocketBase `rides` collection
/// (`pocketbase/pb_migrations/1700000003_rides.js`).
///
/// ```jsonc
/// rides/{rideId} {
///   passenger: relation(users),   // -> passengerId
///   driver: relation(users) | "", // -> driverId
///   status: RideStatus,
///   rideTier: "standard" | "eco" | "premium",
///   pickup: GeoPoint2,             // json
///   dropoff: GeoPoint2,            // json
///   estimate: { distanceKm, durationMin, fareEstimate },  // json
///   fare: {                        // json, populated server-side on completion
///     baseFare, surchargeDzd, totalFare,
///     commissionRate, commissionAmount,
///     driverPayout, companyRevenue, transactionId
///   },
///   pointsAwarded: number,
///   rating: { stars, comment } | null,  // json
///   liveShareToken: string,
///   liveShareExpiresAt, requestedAt, acceptedAt, arrivedAt,
///   startedAt, completedAt, cancelledAt: date (ISO8601 string)
/// }
/// ```
class RideModel {
  final String id;
  final String passengerId;
  final String? driverId;
  final RideStatus status;
  final String rideTier;
  final GeoPoint2 pickup;
  final GeoPoint2 dropoff;
  final RideEstimate estimate;
  final RideFare? fare;
  final int pointsAwarded;
  final RideRating? rating;
  final String? liveShareToken;
  final DateTime? liveShareExpiresAt;
  final DateTime? requestedAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  const RideModel({
    required this.id,
    required this.passengerId,
    required this.status,
    required this.pickup,
    required this.dropoff,
    required this.estimate,
    this.driverId,
    this.rideTier = 'standard',
    this.fare,
    this.pointsAwarded = 0,
    this.rating,
    this.liveShareToken,
    this.liveShareExpiresAt,
    this.requestedAt,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
  });

  factory RideModel.fromMap(String id, Map<String, dynamic> map) {
    final driver = map['driver'] as String?;
    final liveShareToken = map['liveShareToken'] as String?;

    return RideModel(
      id: id,
      passengerId: map['passenger'] as String? ?? '',
      driverId: (driver == null || driver.isEmpty) ? null : driver,
      status: rideStatusFromString(map['status'] as String?),
      rideTier: map['rideTier'] as String? ?? 'standard',
      pickup: GeoPoint2.fromMap(
        (map['pickup'] as Map<String, dynamic>?) ?? const {},
      ),
      dropoff: GeoPoint2.fromMap(
        (map['dropoff'] as Map<String, dynamic>?) ?? const {},
      ),
      estimate: RideEstimate.fromMap(
        (map['estimate'] as Map<String, dynamic>?) ?? const {},
      ),
      fare: map['fare'] == null
          ? null
          : RideFare.fromMap(map['fare'] as Map<String, dynamic>),
      pointsAwarded: (map['pointsAwarded'] as num?)?.toInt() ?? 0,
      rating: map['rating'] == null
          ? null
          : RideRating.fromMap(map['rating'] as Map<String, dynamic>),
      liveShareToken: (liveShareToken == null || liveShareToken.isEmpty) ? null : liveShareToken,
      liveShareExpiresAt: _parseDate(map['liveShareExpiresAt']),
      requestedAt: _parseDate(map['requestedAt']),
      acceptedAt: _parseDate(map['acceptedAt']),
      arrivedAt: _parseDate(map['arrivedAt']),
      startedAt: _parseDate(map['startedAt']),
      completedAt: _parseDate(map['completedAt']),
      cancelledAt: _parseDate(map['cancelledAt']),
    );
  }
}

/// Client-side fare estimate shown during booking (Section: Ride Request Flow).
class RideEstimate {
  final double distanceKm;
  final double durationMin;
  final double fareEstimate;

  const RideEstimate({
    this.distanceKm = 0,
    this.durationMin = 0,
    this.fareEstimate = 0,
  });

  factory RideEstimate.fromMap(Map<String, dynamic> map) => RideEstimate(
        distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 0,
        durationMin: (map['durationMin'] as num?)?.toDouble() ?? 0,
        fareEstimate: (map['fareEstimate'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'distanceKm': distanceKm,
        'durationMin': durationMin,
        'fareEstimate': fareEstimate,
      };
}

/// Server-computed final fare breakdown (Section 6.B), written by the
/// `/api/michwar/rides/{id}/complete` hook route (`pb_hooks/12_rides.pb.js`).
class RideFare {
  final double baseFare;
  final double surchargeDzd;
  final double totalFare; // baseFare + surchargeDzd, paid by passenger
  final double commissionRate; // company's % of baseFare
  final double commissionAmount; // commissionRate * baseFare
  final double driverPayout; // baseFare - commissionAmount
  final double companyRevenue; // commissionAmount + surchargeDzd
  final String transactionId;

  const RideFare({
    required this.baseFare,
    required this.surchargeDzd,
    required this.totalFare,
    required this.commissionRate,
    required this.commissionAmount,
    required this.driverPayout,
    required this.companyRevenue,
    required this.transactionId,
  });

  factory RideFare.fromMap(Map<String, dynamic> map) => RideFare(
        baseFare: (map['baseFare'] as num?)?.toDouble() ?? 0,
        surchargeDzd: (map['surchargeDzd'] as num?)?.toDouble() ?? 0,
        totalFare: (map['totalFare'] as num?)?.toDouble() ?? 0,
        commissionRate: (map['commissionRate'] as num?)?.toDouble() ?? 0,
        commissionAmount: (map['commissionAmount'] as num?)?.toDouble() ?? 0,
        driverPayout: (map['driverPayout'] as num?)?.toDouble() ?? 0,
        companyRevenue: (map['companyRevenue'] as num?)?.toDouble() ?? 0,
        transactionId: map['transactionId'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'baseFare': baseFare,
        'surchargeDzd': surchargeDzd,
        'totalFare': totalFare,
        'commissionRate': commissionRate,
        'commissionAmount': commissionAmount,
        'driverPayout': driverPayout,
        'companyRevenue': companyRevenue,
        'transactionId': transactionId,
      };
}

class RideRating {
  final int stars;
  final String? comment;

  const RideRating({required this.stars, this.comment});

  factory RideRating.fromMap(Map<String, dynamic> map) => RideRating(
        stars: (map['stars'] as num?)?.toInt() ?? 0,
        comment: map['comment'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'stars': stars,
        if (comment != null) 'comment': comment,
      };
}
