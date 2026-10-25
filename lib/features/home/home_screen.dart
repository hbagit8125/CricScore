import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CricScore', style: text.headlineMedium),
              const Spacer(),
              Icon(Icons.sports_cricket, size: 56, color: colors.runs),
              const SizedBox(height: 16),
              Text('No matches yet', style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Start a match and it will be saved here automatically.',
                style: text.bodyMedium?.copyWith(color: colors.muted),
              ),
              const Spacer(),
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
