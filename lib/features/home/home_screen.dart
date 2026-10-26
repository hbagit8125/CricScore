import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/router.dart';
import '../../auth/auth_providers.dart';
import '../../core/preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/glass.dart';
import '../../data/local/app_database.dart';
import '../../data/match_repository.dart';
import '../../data/providers.dart';
import '../../sync/sync_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final matches = ref.watch(matchListProvider);

    return GlassScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const AppLogo(size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('CricScore', style: text.headlineMedium),
                  ),
                  const _SyncIndicator(),
                  const _AccountMenu(),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: switch (matches) {
                  AsyncData(:final value) when value.isEmpty =>
                    const _EmptyState(),
                  AsyncData(:final value) => _MatchList(matches: value),
                  AsyncError() => const Center(
                    child: Text('Saved matches could not be loaded.'),
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.push(Routes.newMatch),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New match'),
              ),
              const _Version(),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Center(
      child: GlassPanel(
        radius: 28,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 72),
            const SizedBox(height: 20),
            Text('No matches yet', style: text.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Start a match and every ball is saved here and to your '
              'account automatically.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchList extends StatelessWidget {
  const _MatchList({required this.matches});

  final List<MatchSummary> matches;

  @override
  Widget build(BuildContext context) {
    // Live matches first, then the rest, each most recent first.
    final live = matches.where((m) => m.status == MatchStatus.inProgress);
    final done = matches.where((m) => m.status == MatchStatus.complete);
    return ListView(
      children: [
        if (live.isNotEmpty) ...[
          const _SectionLabel('In progress'),
          for (final m in live) _MatchTile(match: m, live: true),
        ],
        if (done.isNotEmpty) ...[
          const _SectionLabel('Recent'),
          for (final m in done) _MatchTile(match: m, live: false),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: context.colors.muted,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class _MatchTile extends ConsumerWidget {
  const _MatchTile({required this.match, required this.live});

  final MatchSummary match;
  final bool live;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this match?'),
        content: Text(
          '${match.title} will be deleted from this device and your '
          'account. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmDelete'),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.wicket,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(matchRepositoryProvider).delete(match.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GlassPanel(
        key: Key('match-${match.id}'),
        tint: live ? colors.runs : null,
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        onTap: () => context.push(
          live ? Routes.match(match.id) : Routes.scorecard(match.id),
        ),
        onLongPress: () => _delete(context, ref),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Badge(
                        live ? 'LIVE' : match.format,
                        color: live ? colors.runs : colors.muted,
                      ),
                      if (live) ...[
                        const SizedBox(width: 8),
                        Text(
                          match.format,
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    match.title,
                    style: text.titleLarge?.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 2),
                  Text(match.summary, style: TextStyle(color: colors.muted)),
                ],
              ),
            ),
            _menu(context, ref, colors),
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref, AppColors colors) =>
      PopupMenuButton<void>(
        key: Key('matchMenu-${match.id}'),
        tooltip: 'Match options',
        icon: Icon(Icons.more_vert, color: colors.muted),
        itemBuilder: (context) => [
          if (!live)
            PopupMenuItem<void>(
              onTap: () => context.push(Routes.match(match.id)),
              child: const Text('Open scoring'),
            ),
          PopupMenuItem<void>(
            key: const Key('deleteMatch'),
            onTap: () => _delete(context, ref),
            child: const Text('Delete'),
          ),
        ],
      );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );
}

/// A small cloud icon: hidden when all is uploaded.
class _SyncIndicator extends ConsumerWidget {
  const _SyncIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return switch (ref.watch(syncControllerProvider)) {
      SyncStatus.idle => const SizedBox.shrink(),
      SyncStatus.syncing => Tooltip(
        message: 'Saving to the cloud',
        child: Icon(Icons.cloud_upload_outlined, color: colors.muted),
      ),
      SyncStatus.offline => Tooltip(
        message:
            'Offline. Matches are saved on this device and will upload '
            'when you reconnect.',
        child: Icon(Icons.cloud_off_outlined, color: colors.extras),
      ),
    };
  }
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    return PopupMenuButton<void>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      itemBuilder: (context) => [
        PopupMenuItem<void>(enabled: false, child: Text(user?.label ?? '')),
        PopupMenuItem<void>(
          key: const Key('display'),
          onTap: () => showGlassSheet<void>(context, const _DisplaySheet()),
          child: const Text('Display'),
        ),
        PopupMenuItem<void>(
          onTap: () => ref.read(authServiceProvider).signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

/// Theme and keypad hand, kept on this device.
class _DisplaySheet extends ConsumerWidget {
  const _DisplaySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider).value ?? const Preferences();
    final controller = ref.read(preferencesProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Display', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            SegmentedButton<ThemeChoice>(
              segments: const [
                ButtonSegment(value: ThemeChoice.system, label: Text('Auto')),
                ButtonSegment(value: ThemeChoice.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeChoice.light, label: Text('Light')),
                ButtonSegment(
                  value: ThemeChoice.outdoor,
                  label: Text('Outdoor', key: Key('themeOutdoor')),
                ),
              ],
              selected: {prefs.theme},
              onSelectionChanged: (v) => controller.setTheme(v.single),
            ),
            const SizedBox(height: 4),
            Text(
              'Outdoor is high contrast for bright sunshine.',
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            SwitchListTile(
              key: const Key('leftHanded'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Left-handed keypad'),
              subtitle: const Text('Wicket and undo on the left'),
              value: prefs.leftHanded,
              onChanged: controller.setLeftHanded,
            ),
          ],
        ),
      ),
    );
  }
}

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// "Version 0.3.0 (build 57)", so testers can tell builds apart.
class _Version extends ConsumerWidget {
  const _Version();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(_packageInfoProvider).value;
    if (info == null) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Version ${info.version} (build ${info.buildNumber})',
        key: const Key('version'),
        textAlign: TextAlign.center,
        style: TextStyle(color: context.colors.muted, fontSize: 12),
      ),
    );
  }
}
