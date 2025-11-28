enum PlayerRole { batsman, bowler, allRounder }

class Player {
  String id;
  String name;
  PlayerRole role;

  // Batting Stats
  int runsScored;
  int ballsFaced;
  int fours;
  int sixes;
  bool isOut;
  String? howOut; // e.g., "Bowled by X", "Run out"

  // Bowling Stats
  int runsConceded;
  int wicketsTaken;
  int ballsBowled; // to calculate overs

  Player({
    required this.id,
    required this.name,
    this.role = PlayerRole.batsman,
    this.runsScored = 0,
    this.ballsFaced = 0,
    this.fours = 0,
    this.sixes = 0,
    this.isOut = false,
    this.howOut,
    this.runsConceded = 0,
    this.wicketsTaken = 0,
    this.ballsBowled = 0,
  });

  double get battingStrikeRate {
    if (ballsFaced == 0) return 0.0;
    return (runsScored / ballsFaced) * 100;
  }

  double get economyRate {
    if (ballsBowled == 0) return 0.0;
    double overs = ballsBowled / 6;
    return runsConceded / overs;
  }
}
