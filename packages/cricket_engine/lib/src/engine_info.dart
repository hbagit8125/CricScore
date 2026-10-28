/// Version of the scoring engine's data format.
///
/// Stored with every saved match so older matches can be migrated when the
/// format changes.
///
/// 2: days of play and stoppages (lunch, tea, stumps, rain).
const int engineSchemaVersion = 2;
