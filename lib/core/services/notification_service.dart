/// Push-notification service.
///
/// The Firebase version of MICHWAR used Firebase Cloud Messaging (FCM) for
/// incoming-ride pings, ride-status updates, and SOS escalation. The
/// self-hosted PocketBase backend has no built-in push-notification service
/// (FCM is a Google product and requires a Firebase project), so this is now
/// a minimal no-op stub.
///
/// In-app "real-time" updates (incoming ride requests, status changes,
/// driver location) are instead delivered via PocketBase's realtime
/// subscriptions (`pb.collection(...).subscribe(...)`) — see
/// `RideRepository`. Those work whenever the app is open/foregrounded; they
/// do not wake the app from the background. Re-introducing background push
/// would require a separate push provider (e.g. a self-hosted ntfy/UnifiedPush
/// server) wired into the PocketBase hooks in `pocketbase/pb_hooks/`.
class NotificationService {
  const NotificationService();

  /// No-op: nothing to request without FCM/APNs configured.
  Future<void> requestPermission() async {}
}
