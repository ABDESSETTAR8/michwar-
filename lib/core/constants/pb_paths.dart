/// Single source of truth for PocketBase collection names and the custom
/// `/api/michwar/...` hook routes that replace the old Cloud Functions
/// callables. Keeping these centralized avoids "magic string" typos and
/// keeps the client in sync with `pocketbase/pb_migrations` and
/// `pocketbase/pb_hooks`.
library;

class PbCollections {
  PbCollections._();

  static const String users = 'users';
  static const String drivers = 'drivers';
  static const String rides = 'rides';
  static const String rideStatusHistory = 'ride_status_history';
  static const String wallets = 'wallets';
  static const String walletTransactions = 'wallet_transactions';
  static const String liveShares = 'live_shares';
  static const String sosAlerts = 'sos_alerts';
  static const String heatmapCells = 'heatmap_cells';
}

/// Custom hook routes — see `pocketbase/pb_hooks/*.pb.js`.
class PbRoutes {
  PbRoutes._();

  static String rideAccept(String rideId) => '/api/michwar/rides/$rideId/accept';
  static String rideStatus(String rideId) => '/api/michwar/rides/$rideId/status';
  static String rideComplete(String rideId) => '/api/michwar/rides/$rideId/complete';
  static String rideRate(String rideId) => '/api/michwar/rides/$rideId/rate';
  static String rideShare(String rideId) => '/api/michwar/rides/$rideId/share';

  static const String walletTopup = '/api/michwar/wallet/topup';
  static const String sos = '/api/michwar/sos';
  static const String heatmapPing = '/api/michwar/heatmap/ping';
  static const String role = '/api/michwar/role';
}
