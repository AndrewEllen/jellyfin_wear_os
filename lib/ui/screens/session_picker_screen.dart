import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/jellyfin_constants.dart';
import '../../core/theme/wear_theme.dart';
import '../../core/utils/watch_shape.dart';
import '../../data/models/session_device.dart';
import '../../navigation/app_router.dart';
import '../../state/remote_state.dart';
import '../../state/session_state.dart';
import '../widgets/common/wear_list_view.dart';

/// Screen for selecting a target Jellyfin session to control.
class SessionPickerScreen extends StatefulWidget {
  const SessionPickerScreen({super.key});

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
    JellyfinConstants.log(
      'SessionPicker._selectSession(): '
      'sessionId=${session.sessionId} '
      'deviceName=${session.deviceName} '
      'client=${session.client} '
      'supportsRemoteControl=${session.supportsRemoteControl} '
      'supportsMediaControl=${session.supportsMediaControl} '
      'nowPlaying=${session.nowPlayingItemName}',
    );

    // Update both SessionState AND RemoteState with the target session
    final sessionState = context.read<SessionState>();
    final remoteState = context.read<RemoteState>();

    await sessionState.setTargetSession(session);
    remoteState.setTargetSession(session);

    if (!mounted) return;
    Navigator.pushNamed(context, AppRoutes.remote);
  }

  @override
  Widget build(BuildContext context) {
    final padding = WatchShape.edgePadding(context);

    return Scaffold(
      backgroundColor: WearTheme.background,
      body: Consumer<SessionState>(
        builder: (context, state, _) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
            return Center(
              child: Padding(
                padding: padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 32, color: WearTheme.textSecondary),
                    const SizedBox(height: 8),
                    Text('Failed to load sessions', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      state.errorMessage!,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                      maxLines: 8,
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

          final sessions = state.sessions;

          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.devices_outlined, size: 32, color: WearTheme.textSecondary),
                    const SizedBox(height: 8),
                    Text('No Devices', style: Theme.of(context).textTheme.titleMedium),
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

          return WearListView(
            children: [
              _buildHeader(context, padding),
              ...sessions.map((s) => _buildSessionTile(context, s, padding)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, EdgeInsets padding) {
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Center(
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.devices_outlined, size: 28, color: WearTheme.jellyfinPurple),
              const SizedBox(height: 8),
              Text('Select Device', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionTile(BuildContext context, SessionDevice session, EdgeInsets padding) {
    final subtitleParts = <String>[];
    if (session.client.isNotEmpty) subtitleParts.add(session.client);
    if (session.userName != null && session.userName!.isNotEmpty) subtitleParts.add(session.userName!);
    final subtitle = subtitleParts.isEmpty ? 'Jellyfin Client' : subtitleParts.join(' • ');

    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Center(
        child: Padding(
          padding: padding,
          child: InkWell(
            onTap: () => _selectSession(session),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WearTheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(session.icon, size: 28, color: WearTheme.jellyfinPurple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.deviceName,
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (session.nowPlayingItemName != null && session.nowPlayingItemName!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            session.nowPlayingItemName!,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
