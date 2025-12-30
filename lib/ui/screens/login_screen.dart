import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/wear_theme.dart';
import '../../core/utils/watch_shape.dart';
import '../../data/models/server_info.dart';
import '../../navigation/app_router.dart';
import '../../state/app_state.dart';

/// Login screen for authenticating with a Jellyfin server.
class LoginScreen extends StatefulWidget {
  final LoginScreenArgs? args;

  const LoginScreen({super.key, this.args});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  List<_PublicUser> _publicUsers = [];
  bool _loadingUsers = true;
  _PublicUser? _selectedUser;

  @override
  void initState() {
    super.initState();
    _loadPublicUsers();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPublicUsers() async {
    final serverUrl = widget.args?.serverUrl;
    if (serverUrl == null) {
      setState(() => _loadingUsers = false);
      return;
    }

    try {
      final appState = context.read<AppState>();
      await appState.client.initialize(serverUrl);

      // Fetch public users from the server
      final response = await appState.client.get('/Users/Public');
      final users = response.data as List<dynamic>? ?? [];

      if (!mounted) return;

      setState(() {
        _publicUsers = users
            .map((u) => _PublicUser(
                  id: (u['Id'] ?? '').toString(),
                  name: (u['Name'] ?? 'Unknown').toString(),
                  hasPassword: u['HasPassword'] == true,
                  primaryImageTag: u['PrimaryImageTag']?.toString(),
                  serverUrl: serverUrl,
                ))
            .toList();
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingUsers = false);
    }
  }

  void _selectUser(_PublicUser user) {
    if (!user.hasPassword) {
      // Auto-login if user has no password
      _loginWithUser(user, '');
    } else {
      // Show password prompt
      setState(() {
        _selectedUser = user;
        _passwordController.clear();
        _errorMessage = null;
      });
      // Focus password field after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _passwordFocus.requestFocus();
      });
    }
  }

  void _cancelUserSelection() {
    setState(() {
      _selectedUser = null;
      _passwordController.clear();
      _errorMessage = null;
    });
  }

  Future<void> _loginWithUser(_PublicUser user, String password) async {
    final serverUrl = widget.args?.serverUrl;
    final serverName = widget.args?.serverName ?? 'Server';

    if (serverUrl == null) {
      setState(() => _errorMessage = 'No server URL');
      return;
    }

    // Dismiss keyboard
    _passwordFocus.unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final appState = context.read<AppState>();

      final server = ServerInfo(
        id: '',
        name: serverName,
        address: serverUrl,
      );

      final success = await appState.login(
        server: server,
        username: user.name,
        password: password,
      );

      if (!mounted) return;

      if (success) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.sessionPicker,
          (route) => false,
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = appState.errorMessage ?? 'Login failed';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Connection error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = WatchShape.edgePadding(context);
    final serverName = widget.args?.serverName ?? 'Server';

    // Show password entry if user selected
    if (_selectedUser != null) {
      return _buildPasswordScreen(context, padding, _selectedUser!);
    }

    // Show user picker
    return Scaffold(
      backgroundColor: WearTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                serverName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: WearTheme.textSecondary,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'Select User',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              // Show loading or users
              if (_loadingUsers)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_publicUsers.isEmpty)
                Text(
                  'No users found',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: _publicUsers
                      .map((user) => _buildUserTile(context, user))
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserTile(BuildContext context, _PublicUser user) {
    return GestureDetector(
      onTap: () => _selectUser(user),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Profile picture
          ClipOval(
            child: Container(
              width: 48,
              height: 48,
              color: WearTheme.surface,
              child: user.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: user.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Icon(
                        Icons.person,
                        color: WearTheme.textSecondary,
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.person,
                        color: WearTheme.textSecondary,
                      ),
                    )
                  : const Icon(
                      Icons.person,
                      color: WearTheme.textSecondary,
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user.name,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordScreen(
    BuildContext context,
    EdgeInsets padding,
    _PublicUser user,
  ) {
    return Scaffold(
      backgroundColor: WearTheme.background,
      body: GestureDetector(
        onTap: () => _passwordFocus.unfocus(),
        child: Center(
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Back button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: _cancelUserSelection,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(height: 8),

                // User avatar
                ClipOval(
                  child: Container(
                    width: 40,
                    height: 40,
                    color: WearTheme.surface,
                    child: user.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: user.imageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => const Icon(
                              Icons.person,
                              size: 24,
                              color: WearTheme.textSecondary,
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 24,
                            color: WearTheme.textSecondary,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),

                // Password field
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) =>
                      _loginWithUser(user, _passwordController.text),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () =>
                            _loginWithUser(user, _passwordController.text),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Sign In'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicUser {
  final String id;
  final String name;
  final bool hasPassword;
  final String? primaryImageTag;
  final String serverUrl;

  _PublicUser({
    required this.id,
    required this.name,
    required this.hasPassword,
    required this.serverUrl,
    this.primaryImageTag,
  });

  String? get imageUrl {
    if (primaryImageTag == null || id.isEmpty) return null;
    return '$serverUrl/Users/$id/Images/Primary?maxWidth=100';
  }
}
