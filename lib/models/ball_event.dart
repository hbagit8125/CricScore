enum BallType {
  dot, // 0
  one,
  two,
  three,
  four,
  five, // Overthrows?
  six,
  wide,
  noBall,
  wicket,
  wide4, // Wide + 4 runs
}

class BallEvent {
  final BallType type;
  final int runs; // Runs scored by batsman
  final int extras; // Extra runs
  final bool isWicket;
  final bool isLegalBall;
  final String? wicketType; // e.g., "Bowled", "Caught"

  BallEvent({
    required this.type,
    required this.runs,
    required this.extras,
    required this.isWicket,
    required this.isLegalBall,
    this.wicketType,
  });
}
