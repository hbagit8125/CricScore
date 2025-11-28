import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/match_provider.dart';
import '../models/ball_event.dart';
import '../models/player.dart';
import '../widgets/ball_input_widget.dart';
import '../widgets/player_stats_modal.dart';

class MatchScreen extends StatelessWidget {
  const MatchScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchProvider>(
      builder: (context, match, child) {
        if (!match.isMatchStarted) {
          return const Scaffold(body: Center(child: Text("Match not started")));
        }

        // Check for Over Completion
        // We do this check in build. If over is complete, we should show a dialog or force bowler change.
        // However, showing dialog directly in build is bad.
        // Better to use a button state or separate UI element.
        // We will replace "Play Ball" with "Start New Over" if over is complete.

        return Scaffold(
          backgroundColor: Colors.grey.shade100,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(match.matchName, style: GoogleFonts.poppins(fontSize: 16)),
                Text("${match.battingTeam!.name} vs ${match.bowlingTeam!.name}", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.normal)),
              ],
            ),
            backgroundColor: Colors.green.shade800,
            actions: [
              IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
            ],
          ),
          body: Column(
            children: [
              _buildScoreHeader(match),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                       _buildBatsmenCard(match),
                       _buildBowlerCard(match),
                       _buildRecentBalls(match),
                    ],
                  ),
                ),
              ),
              _buildControlPanel(context, match),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScoreHeader(MatchProvider match) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.shade800,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(match.battingTeam!.name, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16)),
              Text(
                "${match.battingTeam!.totalRuns}/${match.battingTeam!.wicketsLost}",
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("Overs", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16)),
              Text(
                match.battingTeam!.oversPlayed,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
              ),
              Text("CRR: ${(match.battingTeam!.totalRuns / (match.battingTeam!.ballsFaced/6 + 0.1)).toStringAsFixed(2)}", style: GoogleFonts.poppins(color: Colors.white70)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildBatsmenCard(MatchProvider match) {
    return Card(
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildBatsmanRow(match.currentStriker!, true),
            const Divider(),
            _buildBatsmanRow(match.currentNonStriker!, false),
          ],
        ),
      ),
    );
  }

  Widget _buildBatsmanRow(Player player, bool isStriker) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (isStriker) const Icon(Icons.sports_cricket, size: 16, color: Colors.green),
            const SizedBox(width: 8),
            Text(player.name, style: GoogleFonts.poppins(fontWeight: isStriker ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
          ],
        ),
        Text("${player.runsScored}(${player.ballsFaced})", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildBowlerCard(MatchProvider match) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Bowler", style: GoogleFonts.poppins(color: Colors.grey, fontSize: 12)),
                Text(match.currentBowler!.name, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
             Text(
               "${match.currentBowler!.wicketsTaken}/${match.currentBowler!.runsConceded} (${(match.currentBowler!.ballsBowled~/6)}.${match.currentBowler!.ballsBowled%6})",
               style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentBalls(MatchProvider match) {
    return Container(
      height: 60,
      margin: const EdgeInsets.all(16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: match.currentOver.length,
        separatorBuilder: (_,__) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final ball = match.currentOver[index];
          return CircleAvatar(
            backgroundColor: ball.isWicket ? Colors.red : (ball.runs == 4 || ball.runs == 6 ? Colors.green : Colors.grey.shade300),
            foregroundColor: ball.isWicket || ball.runs == 4 || ball.runs == 6 ? Colors.white : Colors.black,
            child: Text(_getBallText(ball), style: const TextStyle(fontWeight: FontWeight.bold)),
          );
        },
      ),
    );
  }

  String _getBallText(BallEvent ball) {
    if (ball.isWicket) return "W";
    if (ball.type == BallType.wide) return "wd";
    if (ball.type == BallType.wide4) return "wd+4";
    if (ball.type == BallType.noBall) return "nb";
    return "${ball.runs}";
  }

  Widget _buildControlPanel(BuildContext context, MatchProvider match) {
    if (match.isOverComplete) {
       return Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: () => _selectNewBowler(context, match),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade800,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text("Start New Over", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (ctx) => BallInputWidget(onInput: (value) => _handleInput(context, value, match)),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text("Play Ball", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _handleInput(BuildContext context, String value, MatchProvider match) {
    Navigator.pop(context); // Close bottom sheet

    BallEvent? event;
    // Map input to BallEvent
    switch (value) {
      case "0": event = BallEvent(type: BallType.dot, runs: 0, extras: 0, isWicket: false, isLegalBall: true); break;
      case "1": event = BallEvent(type: BallType.one, runs: 1, extras: 0, isWicket: false, isLegalBall: true); break;
      case "2": event = BallEvent(type: BallType.two, runs: 2, extras: 0, isWicket: false, isLegalBall: true); break;
      case "3": event = BallEvent(type: BallType.three, runs: 3, extras: 0, isWicket: false, isLegalBall: true); break;
      case "4": event = BallEvent(type: BallType.four, runs: 4, extras: 0, isWicket: false, isLegalBall: true); break;
      case "6": event = BallEvent(type: BallType.six, runs: 6, extras: 0, isWicket: false, isLegalBall: true); break;
      case "WD": event = BallEvent(type: BallType.wide, runs: 0, extras: 1, isWicket: false, isLegalBall: false); break;
      case "WD 4": event = BallEvent(type: BallType.wide4, runs: 0, extras: 5, isWicket: false, isLegalBall: false); break;
      case "NB": event = BallEvent(type: BallType.noBall, runs: 0, extras: 1, isWicket: false, isLegalBall: false); break;
      case "W": event = BallEvent(type: BallType.wicket, runs: 0, extras: 0, isWicket: true, isLegalBall: true, wicketType: "Bowled"); break;
    }

    if (event != null) {
      // Capture player before processing if wicket
      Player? dismissedPlayer;
      if (event.isWicket) {
        dismissedPlayer = match.currentStriker;
      }

      match.processBall(event);

      if (event.isWicket && dismissedPlayer != null) {
        showDialog(
          context: context,
          builder: (_) => PlayerStatsModal(player: dismissedPlayer!)
        ).then((_) {
          // After showing stats, ask for new batsman
          _selectNewBatsman(context, match);
        });
      }
    }
  }

  void _selectNewBatsman(BuildContext context, MatchProvider match) {
    // Determine which players are available (not out and not currently batting)
    final availablePlayers = match.battingTeam!.players.where((p) => !p.isOut && p != match.currentNonStriker).toList();

    if (availablePlayers.isEmpty) {
       // All out logic
       return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Select Next Batsman"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availablePlayers.length,
              itemBuilder: (context, index) {
                final p = availablePlayers[index];
                return ListTile(
                  title: Text(p.name),
                  onTap: () {
                    match.setNewBatsman(p);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _selectNewBowler(BuildContext context, MatchProvider match) {
     // Get players from bowling team, usually anyone can bowl except current bowler?
     // In professional cricket, you can't bowl two consecutive overs.
     final availableBowlers = match.bowlingTeam!.players.where((p) => p != match.currentBowler).toList();

     showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Select Next Bowler"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availableBowlers.length,
              itemBuilder: (context, index) {
                final p = availableBowlers[index];
                return ListTile(
                  title: Text(p.name),
                  subtitle: Text("W: ${p.wicketsTaken} R: ${p.runsConceded}"),
                  onTap: () {
                    match.startNewOver(p);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
