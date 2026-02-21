import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../core/models.dart';
import '../../theme/app_colors.dart';
import '../assignments/assignments_tab.dart';
import '../coordinator/coordinator_dashboard_tab.dart';
import '../coordinator/coordinator_missing_tab.dart';
import '../coordinator/coordinator_operations_tab.dart';
import '../home/home_tab.dart';
import '../map/map_tab.dart';
import '../missing/missing_tab.dart';
import '../profile/profile_tab.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.authState});

  final ClerkAuthState authState;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  String _error = '';
  AppUser? _user;
  late final ApiClient _api;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: AppConfig.baseUrl, tokenProvider: _tokenProvider);
    _bootstrap();
  }

  Future<String?> _tokenProvider() async {
    try {
      final clerk.SessionToken token = await widget.authState.sessionToken();
      return token.jwt;
    } catch (_) {
      return null;
    }
  }

  Future<void> _bootstrap() async {
    try {
      setState(() {
        _loading = true;
        _error = '';
      });

      final syncRaw = await _api.post('/api/auth/sync');
      if (syncRaw is! Map<String, dynamic> ||
          syncRaw['user'] is! Map<String, dynamic>) {
        throw Exception('Invalid sync response from backend');
      }

      var user = AppUser.fromSync(syncRaw['user'] as Map<String, dynamic>);

      try {
        final meRaw = await _api.get('/api/users/me');
        if (meRaw is Map<String, dynamic>) {
          final me = AppUser.fromMe(meRaw);
          user = me.copyWith(
            name: user.name.isNotEmpty ? user.name : me.name,
            email: me.email.isNotEmpty ? me.email : user.email,
          );
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error.isNotEmpty || _user == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 60,
                  color: AppColors.criticalRed,
                ),
                const SizedBox(height: 10),
                Text(
                  _error.isEmpty ? 'Failed to load profile.' : _error,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _bootstrap, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    return RoleBasedAppShell(api: _api, user: _user!);
  }
}

class RoleBasedAppShell extends StatelessWidget {
  const RoleBasedAppShell({super.key, required this.api, required this.user});

  final ApiClient api;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    if (user.isCoordinator) {
      return CoordinatorAppShell(api: api, user: user);
    }
    return GeneralAppShell(api: api, user: user);
  }
}

class GeneralAppShell extends StatefulWidget {
  const GeneralAppShell({super.key, required this.api, required this.user});

  final ApiClient api;
  final AppUser user;

  @override
  State<GeneralAppShell> createState() => _GeneralAppShellState();
}

class _GeneralAppShellState extends State<GeneralAppShell> {
  int _index = 0;

  static const _titles = [
    'Dashboard',
    'Map',
    'Missing',
    'Assignments',
    'Profile',
  ];

  void _showNotifications() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No new notifications.')));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeTab(api: widget.api, user: widget.user),
      MapTab(api: widget.api),
      MissingTab(api: widget.api),
      AssignmentsTab(api: widget.api, user: widget.user),
      ProfileTab(api: widget.api, user: widget.user),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 10,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'lib/assets/favicon.png',
                width: 28,
                height: 28,
              ),
            ),
            const SizedBox(width: 8),
            Text(_titles[_index]),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showNotifications,
            icon: const Icon(Icons.notifications_none),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: ClerkUserButton(),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt),
            label: 'Missing',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Assignments',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class CoordinatorAppShell extends StatefulWidget {
  const CoordinatorAppShell({super.key, required this.api, required this.user});

  final ApiClient api;
  final AppUser user;

  @override
  State<CoordinatorAppShell> createState() => _CoordinatorAppShellState();
}

class _CoordinatorAppShellState extends State<CoordinatorAppShell> {
  int _index = 0;

  static const _titles = [
    'Dashboard',
    'Map',
    'Operations',
    'Missing',
    'Profile',
  ];

  void _showNotifications() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No new notifications.')));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      CoordinatorDashboardTab(api: widget.api, user: widget.user),
      MapTab(api: widget.api),
      CoordinatorOperationsTab(api: widget.api),
      CoordinatorMissingTab(api: widget.api),
      ProfileTab(api: widget.api, user: widget.user),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 10,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'lib/assets/favicon.png',
                width: 28,
                height: 28,
              ),
            ),
            const SizedBox(width: 8),
            Text(_titles[_index]),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showNotifications,
            icon: const Icon(Icons.notifications_none),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                widget.user.role.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: 'Operations',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_search_outlined),
            selectedIcon: Icon(Icons.person_search),
            label: 'Missing',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
