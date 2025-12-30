import 'package:flutter/material.dart';
import '../ui/screens/splash_screen.dart';
import '../ui/screens/server_list_screen.dart';
import '../ui/screens/manual_server_screen.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/library_picker_screen.dart';
import '../ui/screens/library_browse_screen.dart';
import '../ui/screens/item_detail_screen.dart';
import '../ui/screens/session_picker_screen.dart';
import '../ui/screens/remote_screen.dart';
import '../ui/screens/seek_screen.dart';
import '../ui/screens/track_picker_screen.dart';
import '../ui/screens/media_selection_screen.dart';
import '../ui/screens/settings_screen.dart';

/// Named routes for the application.
abstract class AppRoutes {
  static const String splash = '/';
  static const String serverList = '/servers';
  static const String manualServer = '/servers/manual';
  static const String login = '/login';
  static const String libraryPicker = '/library';
  static const String libraryBrowse = '/library/browse';
  static const String itemDetail = '/library/item';
  static const String sessionPicker = '/sessions';
  static const String remote = '/remote';
  static const String seek = '/remote/seek';
  static const String trackPicker = '/remote/tracks';
  static const String mediaSelection = '/remote/media';
  static const String settings = '/settings';
}

/// Route generator for the application.
class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return _buildRoute(const SplashScreen(), settings);

      case AppRoutes.serverList:
        return _buildRoute(const ServerListScreen(), settings);

      case AppRoutes.manualServer:
        return _buildRoute(const ManualServerScreen(), settings);

      case AppRoutes.login:
        final args = settings.arguments as LoginScreenArgs?;
        return _buildRoute(LoginScreen(args: args), settings);

      case AppRoutes.libraryPicker:
        return _buildRoute(const LibraryPickerScreen(), settings);

      case AppRoutes.libraryBrowse:
        final args = settings.arguments as LibraryBrowseArgs?;
        return _buildRoute(LibraryBrowseScreen(args: args), settings);

      case AppRoutes.itemDetail:
        final args = settings.arguments as ItemDetailArgs?;
        return _buildRoute(ItemDetailScreen(args: args), settings);

      case AppRoutes.sessionPicker:
        final args = settings.arguments as SessionPickerArgs?;
        return _buildRoute(SessionPickerScreen(args: args), settings);

      case AppRoutes.remote:
        return _buildRoute(const RemoteScreen(), settings);

      case AppRoutes.seek:
        return _buildRoute(const SeekScreen(), settings);

      case AppRoutes.trackPicker:
        final args = settings.arguments as TrackPickerArgs?;
        return _buildRoute(TrackPickerScreen(args: args), settings);

      case AppRoutes.mediaSelection:
        return _buildRoute(const MediaSelectionScreen(), settings);

      case AppRoutes.settings:
        return _buildRoute(const SettingsScreen(), settings);

      default:
        return _buildRoute(
          Scaffold(
            body: Center(
              child: Text('Route not found: ${settings.name}'),
            ),
          ),
          settings,
        );
    }
  }

  static PageRoute<T> _buildRoute<T>(Widget page, RouteSettings settings) {
    return MaterialPageRoute<T>(
      builder: (_) => page,
      settings: settings,
    );
  }
}

/// Arguments for the login screen.
class LoginScreenArgs {
  final String serverUrl;
  final String? serverName;

  const LoginScreenArgs({
    required this.serverUrl,
    this.serverName,
  });
}

/// Arguments for the library browse screen.
class LibraryBrowseArgs {
  final String parentId;
  final String title;
  final String? mediaType;

  const LibraryBrowseArgs({
    required this.parentId,
    required this.title,
    this.mediaType,
  });
}

/// Arguments for the item detail screen.
class ItemDetailArgs {
  final String itemId;
  final String? title;

  const ItemDetailArgs({
    required this.itemId,
    this.title,
  });
}

/// Arguments for the track picker screen.
class TrackPickerArgs {
  final bool isAudio;

  const TrackPickerArgs({
    required this.isAudio,
  });
}

/// Arguments for the session picker screen.
class SessionPickerArgs {
  /// Item ID to play after session selection (optional).
  final String? itemIdToPlay;

  /// Item name for display (optional).
  final String? itemName;

  const SessionPickerArgs({
    this.itemIdToPlay,
    this.itemName,
  });
}
