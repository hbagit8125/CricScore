import 'player.dart';

class Team {
  String name;
  List<Player> players;
  int totalRuns;
  int wicketsLost;
  int ballsFaced; // Legal balls + extras that count as balls (not wide/no ball)
  int extras;

  Team({
    required this.name,
    required this.players,
    this.totalRuns = 0,
    this.wicketsLost = 0,
    this.ballsFaced = 0,
    this.extras = 0,
  });

  String get oversPlayed {
    int overs = ballsFaced ~/ 6;
    int balls = ballsFaced % 6;
    return "$overs.$balls";
  }
}
