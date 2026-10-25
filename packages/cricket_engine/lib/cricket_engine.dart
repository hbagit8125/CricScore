/// Scoring engine for CricScore.
///
/// Holds the Laws-based scoring rules, match configuration and the ball log
/// replay. It has no Flutter dependency so it can be tested and reused on its
/// own.
library;

export 'src/engine/errors.dart';
export 'src/engine/match.dart';
export 'src/engine_info.dart';
export 'src/model/events.dart';
export 'src/model/match_setup.dart';
export 'src/model/team.dart';
export 'src/rules/match_rules.dart';
export 'src/serialization/match_json.dart';
export 'src/state/cards.dart';
export 'src/state/innings_state.dart';
export 'src/state/match_state.dart';
export 'src/state/pending.dart';
export 'src/state/result.dart';
