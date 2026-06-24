/// Single source of truth for Firestore collection names and Cloud
/// Function callable names. Keeps strings DRY across repositories and
/// mirrors the security rules in `firestore.rules`.
library;

class FsCollections {
  FsCollections._();

  static const String users = 'users';
  static const String drivers = 'drivers';
  static const String rides = 'rides';
  static const String rideStatusHistory = 'ride_status_history';
  static const String wallets = 'wallets';
  static const String walletTransactions = 'wallet_transactions';
  static const String liveShares = 'live_shares';
  static const String sosAlerts = 'sos_alerts';
  static const String heatmapCells = 'heatmap_cells';
  static const String rateLimits = 'rate_limits';
}

/// Cloud Function callable names (see functions/src/index.ts).
class FsFunctions {
  FsFunctions._();

  static const String acceptRide = 'acceptRide';
  static const String updateRideStatus = 'updateRideStatus';
  static const String completeRide = 'completeRide';
  static const String rateRide = 'rateRide';
  static const String shareRide = 'shareRide';
  static const String topUpWallet = 'topUpWallet';
  static const String triggerSos = 'triggerSos';
  static const String pingHeatmap = 'pingHeatmap';
  static const String switchRole = 'switchRole';
  static const String seedDemoAccounts = 'seedDemoAccounts';
}
