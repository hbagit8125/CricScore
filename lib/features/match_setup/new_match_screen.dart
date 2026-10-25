import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Placeholder until match setup is built in phase P3.
class NewMatchScreen extends StatelessWidget {
  const NewMatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New match')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Match setup arrives with the new scoring screens.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted),
          ),
        ),
      ),
    );
  }
}
