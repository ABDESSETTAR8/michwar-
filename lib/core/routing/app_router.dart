import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/driver_model.dart';
import '../models/user_model.dart';
import '../providers/app_providers.dart';
import '../../features/authentication/presentation/screens/splash_screen.dart';
import '../../features/authentication/presentation/screens/welcome_screen.dart';
import '../../features/authentication/presentation/screens/login_screen.dart';
import '../../features/authentication/presentation/screens/signup_screen.dart';
import '../../features/authentication/presentation/screens/role_selection_screen.dart';
import '../../features/authentication/presentation/screens/document_upload_screen.dart';
import '../../features/passenger/presentation/screens/passenger_home_screen.dart';
import '../../features/passenger/presentation/screens/destination_search_screen.dart';
import '../../features/passenger/presentation/screens/ride_options_screen.dart';
import '../../features/passenger/presentation/screens/booking_confirmation_screen.dart';
import '../../features/passenger/presentation/screens/active_ride_screen.dart';
import '../../features/passenger/presentation/screens/post_ride_screen.dart';
import '../../features/passenger/presentation/screens/loyalty_dashboard_screen.dart';
import '../../features/driver/presentation/screens/driver_home_screen.dart';
import '../../features/driver/presentation/screens/driver_active_ride_screen.dart';
import '../../features/driver/presentation/screens/earnings_dashboard_screen.dart';
import '../../features/driver/presentation/screens/heading_home_settings_screen.dart';
import '../../features/driver/presentation/screens/wallet_screen.dart';
import '../../features/shared/presentation/screens/settings_screen.dart';
import '../../features/shared/presentation/screens/support_screen.dart';
import '../../features/shared/presentation/screens/sos_contacts_screen.dart';

/// Route names — referenced via `context.goNamed(...)` so paths can change
/// without breaking call sites.
class AppRoutes {
  AppRoutes._();

  static const splash = 'splash';
  static const welcome = 'welcome';
  static const login = 'login';
  static const signup = 'signup';
  static const roleSelection = 'roleSelection';
  static const documentUpload = 'documentUpload';

  static const passengerHome = 'passengerHome';
  static const destinationSearch = 'destinationSearch';
  static const rideOptions = 'rideOptions';
  static const bookingConfirmation = 'bookingConfirmation';
  static const activeRide = 'activeRide';
  static const postRide = 'postRide';
  static const loyaltyDashboard = 'loyaltyDashboard';

  static const driverHome = 'driverHome';
  static const driverActiveRide = 'driverActiveRide';
  static const earningsDashboard = 'earningsDashboard';
  static const headingHomeSettings = 'headingHomeSettings';
  static const wallet = 'wallet';

  static const settings = 'settings';
  static const support = 'support';
  static const sosContacts = 'sosContacts';
}

/// Builds the app's [GoRouter], reacting to auth/role state so users land
/// on the correct "Home" environment (Section: "Implementation Roadmap" —
/// role-based routing).
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final userProfile = ref.watch(userProfileProvider);
  final driverProfile = ref.watch(driverProfileProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    refreshListenable: GoRouterRefreshStream(ref),
    redirect: (context, state) {
      final loggedIn = authState.value != null;
      final loggingInPaths = {
        '/welcome',
        '/auth/login',
        '/auth/signup',
      };
      final atSplash = state.matchedLocation == '/';

      // Auth error → send to welcome.
      if (authState.hasError) {
        return loggingInPaths.contains(state.matchedLocation) || atSplash
            ? '/welcome'
            : null;
      }

      // Profile error while LOGGED IN (e.g. Firestore rules not deployed yet) →
      // fall through to home rather than bouncing back to welcome.
      if (userProfile.hasError && loggedIn) {
        if (loggingInPaths.contains(state.matchedLocation) || atSplash) {
          return '/passenger'; // safest fallback
        }
        return null; // stay wherever the user is
      }

      // Profile error while NOT logged in → welcome.
      if (userProfile.hasError) {
        return loggingInPaths.contains(state.matchedLocation) || atSplash
            ? '/welcome'
            : null;
      }

      // Still resolving auth state -> stay on splash.
      if (authState.isLoading) return atSplash ? null : '/';

      if (!loggedIn) {
        if (loggingInPaths.contains(state.matchedLocation) || atSplash) {
          return atSplash ? '/welcome' : null;
        }
        return '/welcome';
      }

      // Logged in but profile still loading.
      if (userProfile.isLoading) return atSplash ? null : '/';

      final profile = userProfile.value;
      if (profile == null) {
        // Profile record not yet loaded — stay on splash until it arrives.
        return atSplash ? null : '/';
      }

      // Brand-new accounts (role defaults to 'passenger' on signup but
      // haven't confirmed it yet) go to Role Selection first.
      if (!profile.roleSelected) {
        return state.matchedLocation == '/role-selection'
            ? null
            : '/role-selection';
      }

      // If user is logged in but still on an auth screen, send them home.
      if (loggingInPaths.contains(state.matchedLocation) ||
          atSplash ||
          state.matchedLocation == '/role-selection') {
        return profile.role == UserRole.driver ? '/driver' : '/passenger';
      }

      // Drivers whose verification documents are missing/pending are
      // routed to the upload portal before reaching the driver home.
      if (profile.role == UserRole.driver) {
        final driver = driverProfile.value;
        final needsDocs = driver != null &&
            driver.verificationStatus == DriverVerificationStatus.pending &&
            state.matchedLocation != '/driver/documents' &&
            !state.matchedLocation.startsWith('/settings') &&
            !state.matchedLocation.startsWith('/support');
        if (needsDocs) return '/driver/documents';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        name: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        name: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/signup',
        name: AppRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/role-selection',
        name: AppRoutes.roleSelection,
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/driver/documents',
        name: AppRoutes.documentUpload,
        builder: (context, state) => const DocumentUploadScreen(),
      ),

      // --- Passenger ---
      GoRoute(
        path: '/passenger',
        name: AppRoutes.passengerHome,
        builder: (context, state) => const PassengerHomeScreen(),
      ),
      GoRoute(
        path: '/passenger/destination',
        name: AppRoutes.destinationSearch,
        builder: (context, state) => const DestinationSearchScreen(),
      ),
      GoRoute(
        path: '/passenger/ride-options',
        name: AppRoutes.rideOptions,
        builder: (context, state) => RideOptionsScreen(
          args: state.extra as RideOptionsArgs,
        ),
      ),
      GoRoute(
        path: '/passenger/booking-confirmation',
        name: AppRoutes.bookingConfirmation,
        builder: (context, state) => BookingConfirmationScreen(
          args: state.extra as BookingConfirmationArgs,
        ),
      ),
      GoRoute(
        path: '/passenger/active-ride/:rideId',
        name: AppRoutes.activeRide,
        builder: (context, state) => ActiveRideScreen(
          rideId: state.pathParameters['rideId']!,
        ),
      ),
      GoRoute(
        path: '/passenger/post-ride/:rideId',
        name: AppRoutes.postRide,
        builder: (context, state) => PostRideScreen(
          rideId: state.pathParameters['rideId']!,
        ),
      ),
      GoRoute(
        path: '/passenger/loyalty',
        name: AppRoutes.loyaltyDashboard,
        builder: (context, state) => const LoyaltyDashboardScreen(),
      ),

      // --- Driver ---
      GoRoute(
        path: '/driver',
        name: AppRoutes.driverHome,
        builder: (context, state) => const DriverHomeScreen(),
      ),
      GoRoute(
        path: '/driver/active-ride/:rideId',
        name: AppRoutes.driverActiveRide,
        builder: (context, state) => DriverActiveRideScreen(
          rideId: state.pathParameters['rideId']!,
        ),
      ),
      GoRoute(
        path: '/driver/earnings',
        name: AppRoutes.earningsDashboard,
        builder: (context, state) => const EarningsDashboardScreen(),
      ),
      GoRoute(
        path: '/driver/heading-home',
        name: AppRoutes.headingHomeSettings,
        builder: (context, state) => const HeadingHomeSettingsScreen(),
      ),
      GoRoute(
        path: '/driver/wallet',
        name: AppRoutes.wallet,
        builder: (context, state) => const WalletScreen(),
      ),

      // --- Shared ---
      GoRoute(
        path: '/settings',
        name: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/support',
        name: AppRoutes.support,
        builder: (context, state) => const SupportScreen(),
      ),
      GoRoute(
        path: '/settings/sos-contacts',
        name: AppRoutes.sosContacts,
        builder: (context, state) => const SosContactsScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod streams to a [Listenable] so [GoRouter] re-evaluates
/// `redirect` whenever auth or profile state changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Ref ref) {
    _listeners = [
      ref.listen(authStateProvider, (_, __) => notifyListeners()),
      ref.listen(userProfileProvider, (_, __) => notifyListeners()),
      ref.listen(driverProfileProvider, (_, __) => notifyListeners()),
    ];
  }
  late final List<dynamic> _listeners;
}
