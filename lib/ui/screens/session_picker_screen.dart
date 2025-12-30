import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/jellyfin_constants.dart';
import '../../core/theme/wear_theme.dart';
import '../../data/models/session_device.dart';
import '../../navigation/app_router.dart';
import '../../state/remote_state.dart';
import '../../state/session_state.dart';
import '../widgets/common/rotary_wheel_list.dart';

/// Screen for selecting a target Jellyfin session to control.
///
/// Uses RotaryWheelList for a Wear-style wheel list with scale/fade effect.
class SessionPickerScreen extends StatefulWidget {
  final SessionPickerArgs? args;

  const SessionPickerScreen({super.key, this.args});

  @override
  State<SessionPickerScreen> createState() => _SessionPickerScreenState();
}

class _SessionPickerScreenState extends State<SessionPickerScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<SessionState>().refreshSessions();
    });
  }

  Future<void> _selectSession(SessionDevice session) async {
    HapticFeedback.mediumImpact();

    final itemIdToPlay = widget.args?.itemIdToPlay;
    final itemName = widget.args?.itemName;

    JellyfinConstants.log(
      '========== SESSION SELECTED ==========\n'
      '  sessionId: ${session.sessionId}\n'
      '  deviceName: ${session.deviceName}\n'
      '  client: ${session.client}\n'
      '  supportsRemoteControl: ${session.supportsRemoteControl}\n'
      '  supportsMediaControl: ${session.supportsMediaControl}\n'
      '  nowPlaying: ${session.nowPlayingItemName}\n'
      '  itemIdToPlay: $itemIdToPlay\n'
      '  itemName: $itemName',
    );

    // Update both SessionState AND RemoteState with the target session
    final sessionState = context.read<SessionState>();
    final remoteState = context.read<RemoteState>();

    await sessionState.setTargetSession(session);
    remoteState.setTargetSession(session);

    // If an item ID was passed, play it on the selected session
    if (itemIdToPlay != null && itemIdToPlay.isNotEmpty) {
      JellyfinConstants.log(
        'Playing item $itemIdToPlay ($itemName) on session ${session.sessionId}',
      );
      final success = await sessionState.playOnTarget([itemIdToPlay]);
      JellyfinConstants.log('Play command result: $success');
    }

    if (!mounted) return;
    Navigator.pushNamed(context, AppRoutes.remote);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WearTheme.background,
      body: Consumer<SessionState>(
        builder: (context, state, _) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
            return _buildErrorState(state.errorMessage!);
          }

          final sessions = state.sessions;

          if (sessions.isEmpty) {
            return _buildEmptyState();
          }

          return RotaryWheelList<SessionDevice>(
            items: sessions,
            itemExtent: 90,
            onItemTap: (session, index) => _selectSession(session),
            itemBuilder: (context, session, index, isCentered) {
              return _buildSessionCard(session, isCentered);
            },
          );
        },
      ),
    );
  }

  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 32,
              color: WearTheme.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              'Failed to load sessions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => context.read<SessionState>().refreshSessions(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.devices_outlined,
              size: 32,
              color: WearTheme.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              'No Devices',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'No active Jellyfin\nclients found',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => context.read<SessionState>().refreshSessions(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(SessionDevice session, bool isCentered) {
    final subtitleParts = <String>[];
    if (session.client.isNotEmpty) subtitleParts.add(session.client);
    if (session.userName != null && session.userName!.isNotEmpty) {
      subtitleParts.add(session.userName!);
    }
    final subtitle =
        subtitleParts.isEmpty ? 'Jellyfin Client' : subtitleParts.join(' • ');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCentered ? WearTheme.surface : WearTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: isCentered
            ? Border.all(color: WearTheme.jellyfinPurple, width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          Icon(
            session.icon,
            size: 28,
            color: isCentered ? WearTheme.jellyfinPurple : WearTheme.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.deviceName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: isCentered ? FontWeight.bold : null,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: WearTheme.textSecondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (session.nowPlayingItemName != null &&
                    session.nowPlayingItemName!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '▶ ${session.nowPlayingItemName!}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: WearTheme.jellyfinPurple,
                          fontSize: 10,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
