import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/player.dart';

class PlayerStatsModal extends StatelessWidget {
  final Player player;

  const PlayerStatsModal({Key? key, required this.player}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(player.name, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(player.howOut ?? "Out", style: GoogleFonts.poppins(fontSize: 16, color: Colors.red)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem("Runs", "${player.runsScored}"),
                _buildStatItem("Balls", "${player.ballsFaced}"),
                _buildStatItem("4s", "${player.fours}"),
                _buildStatItem("6s", "${player.sixes}"),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              "Strike Rate: ${player.battingStrikeRate.toStringAsFixed(1)}",
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                shape: const StadiumBorder(),
                backgroundColor: Colors.black,
              ),
              child: const Text("Close"),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
