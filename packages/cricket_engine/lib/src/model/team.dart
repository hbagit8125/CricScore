/// A player as the engine sees them: a stable id and a display name.
final class PlayerRef {
  const PlayerRef({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is PlayerRef && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'PlayerRef($id, $name)';
}

/// A team's playing side. List order is the intended batting order.
final class TeamSheet {
  TeamSheet({
    required this.id,
    required this.name,
    required List<PlayerRef> players,
    List<PlayerRef> substitutes = const [],
  }) : players = List.unmodifiable(players),
       substitutes = List.unmodifiable(substitutes);

  final String id;
  final String name;
  final List<PlayerRef> players;

  /// Named substitutes who may replace a player during the match
  /// (concussion replacement, impact player). They can also field.
  final List<PlayerRef> substitutes;

  /// Playing side and substitutes.
  Iterable<PlayerRef> get squad => [...players, ...substitutes];

  bool hasPlayer(String playerId) => players.any((p) => p.id == playerId);

  PlayerRef player(String playerId) =>
      players.firstWhere((p) => p.id == playerId);
}
