import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/local/app_database.dart';
import '../../data/match_repository.dart';
import '../../data/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final matches = ref.watch(matchListProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('CricScore', style: text.headlineMedium),
              const SizedBox(height: 16),
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
              FilledButton(
                onPressed: () => context.push(Routes.newMatch),
                child: const Text('New match'),
              ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.sports_cricket, size: 56, color: colors.runs),
        const SizedBox(height: 16),
        Text('No matches yet', style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Start a match and it will be saved here automatically.',
          style: text.bodyMedium?.copyWith(color: colors.muted),
        ),
      ],
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

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.live});

  final MatchSummary match;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Card(
      color: colors.surface,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(match.title),
        subtitle: Text('${match.format} · ${match.summary}'),
        trailing: live
            ? Icon(Icons.circle, size: 10, color: colors.runs)
            : null,
      ),
    );
  }
}
