# Cricsheet fixtures

These files are ball-by-ball match data from [Cricsheet](https://cricsheet.org), gzip-compressed and otherwise unchanged. They are used only to test that the engine reproduces the published scorecards.

Cricsheet data is made available under the [Open Data Commons Attribution License](http://opendatacommons.org/licenses/by/1.0/). Data © Cricsheet contributors.

| File | Match |
|---|---|
| 1144530 | England v New Zealand, ODI World Cup final, 14 July 2019 (tie, super over, boundary count) |
| 1384429 | Sri Lanka v Bangladesh, ODI, 6 November 2023 (timed out) |
| 1420222 | Canada v Nepal, ODI, 12 February 2024 (penalty runs) |
| 1059712 | Zimbabwe v West Indies, ODI, 19 November 2016 (tie) |
| 1127284 | Ireland v Pakistan, Test, 11 May 2018 (follow-on after lost time) |
| 1022593 | West Indies v India, Test, 21 July 2016 (follow-on, innings win) |
| 1020041 | New Zealand v South Africa, Test, 8 March 2017 (draw) |
| 1000855 | Australia v South Africa, Test, 24 November 2016 (declaration) |
| 1417818 | London Spirit v Northern Superchargers, The Hundred, 13 August 2024 (rain) |
| 1417822 | Southern Brave v Birmingham Phoenix, The Hundred, 17 August 2024 (super over) |
| 1370351 | Mumbai Indians v Lucknow Super Giants, IPL, 24 May 2023 (impact players) |
| 1136564 | Rajasthan Royals v Sunrisers Hyderabad, IPL, 9 April 2018 (seven-ball over) |
| 1552859 | India v Japan, T20I, 22 September 2026 (five overs a side) |

To replay a whole Cricsheet download locally (not run in CI):

```
CRICSHEET_DIR=/path/to/unzipped/json dart test test/cricsheet_bulk_test.dart
```
