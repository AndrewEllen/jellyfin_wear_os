import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/wear_theme.dart';
import '../../navigation/app_router.dart';
import '../../state/app_state.dart';

/// Initial splash screen shown on app launch.
/// Attempts to restore previous session and navigates accordingly.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Brief delay to show splash
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Try to restore session from stored credentials
    final appState = context.read<AppState>();
    final success = await appState.tryAutoConnect();

    if (!mounted) return;

    if (success) {
      // We have valid auth, go to session picker
      Navigator.of(context).pushReplacementNamed(AppRoutes.sessionPicker);
    } else {
      // No valid auth, go to server list
      Navigator.of(context).pushReplacementNamed(AppRoutes.serverList);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WearTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Jellyfin icon placeholder
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: WearTheme.jellyfinPurple,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.play_circle_filled,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Jellyfin',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
