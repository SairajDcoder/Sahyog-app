import 'dart:async';

import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../theme/app_colors.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.api, required this.user});

  final ApiClient api;
  final AppUser user;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _trackingEnabled = false;
  bool _busy = false;
  bool _availability = true;

  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _availability = widget.user.isActive;
    _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_trackingEnabled && mounted) {
        _syncLocationOnce(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncLocationOnce({bool silent = false}) async {
    try {
      if (!silent) setState(() => _busy = true);

      final location = await LocationService().getCurrentPosition();

      await widget.api.put(
        '/api/users/me/location',
        body: {'lat': location.latitude, 'lng': location.longitude},
      );

      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location synced successfully')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Location sync failed: $e')));
      }
    } finally {
      if (mounted && !silent) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    try {
      setState(() => _busy = true);
      final raw = await widget.api.patch(
        '/api/users/me/availability',
        body: {'is_active': value},
      );
      if (!mounted) return;

      final next = (raw is Map<String, dynamic> && raw['is_active'] is bool)
          ? raw['is_active'] as bool
          : value;
      setState(() => _availability = next);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'You are now marked active.'
                : 'You are now marked inactive.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _availability = !_availability);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Availability update failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final auth = ClerkAuth.of(context, listen: false);
    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVolunteer = widget.user.isVolunteer;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClerkAuthBuilder(
          signedInBuilder: (context, authState) {
            final clerkUser = authState.user;

            final name = clerkUser?.name ?? widget.user.name;
            final email = clerkUser?.email ?? widget.user.email;
            final imageUrl = clerkUser?.imageUrl;

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: AppColors.primaryGreen.withValues(
                        alpha: 0.15,
                      ),
                      backgroundImage: imageUrl != null
                          ? NetworkImage(imageUrl)
                          : null,
                      child: imageUrl == null
                          ? const Icon(
                              Icons.person,
                              size: 45,
                              color: AppColors.primaryGreen,
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      email.isEmpty ? 'No email linked' : email,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Chip(
                      backgroundColor: AppColors.primaryGreen.withValues(
                        alpha: 0.1,
                      ),
                      label: Text(
                        widget.user.role.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          signedOutBuilder: (_, __) => const SizedBox.shrink(),
        ),

        const SizedBox(height: 16),

        if (isVolunteer)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  value: _availability,
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() => _availability = value);
                          _toggleAvailability(value);
                        },
                  title: const Text('Volunteer Availability'),
                  subtitle: const Text(
                    'Reflects directly to server live status.',
                  ),
                ),
                SwitchListTile(
                  value: _trackingEnabled,
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() => _trackingEnabled = value);
                          if (value) _syncLocationOnce();
                        },
                  title: const Text('Enable Location Sync'),
                  subtitle: const Text(
                    'Required for live disaster monitoring.',
                  ),
                ),
                if (_trackingEnabled)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 16,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _syncLocationOnce,
                        icon: const Icon(Icons.my_location),
                        label: const Text('Sync Now'),
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Availability and location toggle are enabled only for volunteer login.',
              ),
            ),
          ),

        const SizedBox(height: 16),

        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ExpansionTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('Manage Account'),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: ClerkOrganizationList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            label: const Text('Sign Out'),
          ),
        ),
      ],
    );
  }
}
