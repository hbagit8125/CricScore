import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../models/ball_event.dart';

class MatchProvider with ChangeNotifier {
  String matchName = "New Match";
  int playersPerTeam = 11;

  Team? teamA;
  Team? teamB;

  bool isMatchStarted = false;

  // Current Inning State
  Team? battingTeam;
  Team? bowlingTeam;

  Player? currentStriker;
  Player? currentNonStriker;
  Player? currentBowler;

  List<BallEvent> currentOver = [];
  List<List<BallEvent>> inningsHistory = [];

  bool get isOverComplete => currentOver.where((e) => e.isLegalBall).length >= 6;

  // Setup Match
  void initMatch(String name, int playerCount, String teamAName, String teamBName, List<Player> playersA, List<Player> playersB) {
    matchName = name;
    playersPerTeam = playerCount;
    teamA = Team(name: teamAName, players: playersA);
    teamB = Team(name: teamBName, players: playersB);
    isMatchStarted = false;
    notifyListeners();
  }

  void startMatch(Team batting, Team bowling, Player striker, Player nonStriker, Player bowler) {
    battingTeam = batting;
    bowlingTeam = bowling;
    currentStriker = striker;
    currentNonStriker = nonStriker;
    currentBowler = bowler;
    isMatchStarted = true;
    notifyListeners();
  }

  // Core Logic: Process Ball
  void processBall(BallEvent event) {
    if (battingTeam == null || currentStriker == null || currentBowler == null) return;

    // Handle Wide 4 Logic (5 runs total, 1 extra, 4 runs not to batsman usually but extra runs are 5.
    // Wait, usually Wide 4 means 5 wides. If it hits bat it's not wide.
    // Assuming user means "Wide ball that goes for 4 byes" -> 5 Wides total)
    // Or "Wide + 4" meaning 5 runs to team, 5 extras.

    int runsFromBat = event.runs;
    int extras = event.extras;
    if (event.type == BallType.wide4) {
      extras = 5; // 1 wide + 4 boundary
      runsFromBat = 0;
    }

    // Update Team Score
    int totalRunsToAdd = runsFromBat + extras;
    battingTeam!.totalRuns += totalRunsToAdd;
    battingTeam!.extras += extras;

    // Update Bowler Stats
    currentBowler!.runsConceded += totalRunsToAdd;
    if (event.isLegalBall) {
      currentBowler!.ballsBowled++;
      battingTeam!.ballsFaced++;
    }
    if (event.isWicket && event.wicketType != "Run Out") {
      currentBowler!.wicketsTaken++;
    }

    // Update Batsman Stats
    if (event.type != BallType.wide && event.type != BallType.wide4) {
       // Wides are not balls faced by batsman
       // No ball IS faced.
       currentStriker!.ballsFaced++;
    }

    currentStriker!.runsScored += runsFromBat;
    if (runsFromBat == 4) currentStriker!.fours++;
    if (runsFromBat == 6) currentStriker!.sixes++;

    // Add to history
    currentOver.add(event);

    // Handle Wicket
    if (event.isWicket) {
      currentStriker!.isOut = true;
      currentStriker!.howOut = event.wicketType;
      battingTeam!.wicketsLost++;
    }

    // Handle Strike Rotation Logic
    bool shouldSwap = false;
    if (runsFromBat % 2 != 0) {
      shouldSwap = !shouldSwap;
    }

    // Check for Over Completion
    if (currentOver.where((e) => e.isLegalBall).length >= 6) {
       // End of over always swaps ends
       shouldSwap = !shouldSwap;
    }

    if (shouldSwap) {
       _swapStrike();
    }

    // NOTE: We do not clear the current over here immediately if we want to show it in UI until next bowler starts
    // But for logic flow, we mark it.

    notifyListeners();
  }

  void startNewOver(Player newBowler) {
    if (currentOver.isNotEmpty) {
      inningsHistory.add(List.from(currentOver));
      currentOver.clear();
    }
    currentBowler = newBowler;
    notifyListeners();
  }

  void _swapStrike() {
    // If one player is out, we simply swap the reference variables.
    // If 'currentStriker' is the one who got out, he is now in 'currentNonStriker' position (logic-wise for the variable swap),
    // but visually and logically we need to replace the OUT player.
    //
    // Actually, simpler: just swap the variables. The UI will prompt to replace the OUT player.
    // If `currentStriker` was out, after swap `currentNonStriker` is the OUT player.
    // The UI `setNewBatsman` needs to know which slot to fill.

    final temp = currentStriker;
    currentStriker = currentNonStriker;
    currentNonStriker = temp;
  }

  void setNewBatsman(Player player) {
    // We need to replace the player who is OUT.
    if (currentStriker != null && currentStriker!.isOut) {
      currentStriker = player;
    } else if (currentNonStriker != null && currentNonStriker!.isOut) {
      currentNonStriker = player;
    } else {
      // Fallback or initial set (though initial set uses startMatch)
      // If neither is out (e.g. retired hurt or just force change), default to striker?
      // Assuming standard wicket flow:
      currentStriker = player;
    }
    notifyListeners();
  }
}
