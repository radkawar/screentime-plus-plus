# Mac Screen Time import

## Findings on this Mac

Investigated on 2026-10-24, macOS 27.2 (26B5086k). These are observed local results, not a promise about other macOS releases or installations.

- `~/Library/Application Support/Knowledge/knowledgeC.db` exists (23,474,176 bytes). `ls` and `sqlite3 -readonly` succeeded from the development shell.
- `ZOBJECT` contains `/app/usage`: 10,000 rows from **2026-10-07 15:17:41 UTC through 2026-10-12 05:49:09 UTC**. The database also has newer `/app/mediaUsage` records through October 24. File modification time therefore does **not** establish freshness of app usage.
- `/app/usage` contains bundle identifiers in `ZVALUESTRING`, interval endpoints in `ZSTARTDATE` and `ZENDDATE`, and timestamps measured in seconds since 2001-01-01 UTC. A `ZSOURCE` join returned no populated source/device metadata for these 10,000 rows.
- 1,065 rows have nonpositive durations; none have null bundle identifiers or end dates. Two pairs of positive-duration intervals overlap. An importer must not blindly sum every row.
- `~/Library/Biome/streams/restricted/App.InFocus/local/` is readable here. It contains 13 numbered 524,288-byte files and a `tombstone` directory, with numbered files dated October 1–16.
- Reading 64 bytes of the latest numbered file with `xxd -l 64` succeeded. It begins `53 45 47 42` (`SEGB`), not SQLite, and contains binary record data. This investigation did not decode its records or establish their coverage.

Commands used included `ls -ld`, `ls -l`, `sqlite3 -readonly` schema/count/time-range/provenance/overlap queries, `xxd -l 64`, and `sw_vers`. None modified Apple's history or imported into the user's Screentime++ database.

## Shipped behavior

**Settings → Privacy → Import Mac App History** offers a deliberate, confirmed, one-time import from the Knowledge database. It describes the history as incomplete and potentially stale, rather than promising parity with Screen Time.

- Opens Apple's database with `SQLITE_OPEN_READONLY`, without changing journal settings or copying a live database separately from its WAL. The read query sees committed SQLite data, including WAL data.
- Reads only `/app/usage`, not browsing, media, titles, content, or Biome. Excludes records with explicit device identifiers rather than risk importing another device's usage; unidentified records in the local Knowledge store are accepted. Absence of device metadata is not a guarantee of provenance on every macOS version.
- Uses the 2001 reference epoch, clips to the selected retention period and import time, and skips empty identifiers and invalid/nonpositive intervals.
- Imports only time before the earliest existing Screentime++ segment, so historical data cannot double count recordings made by this app. Overlapping source intervals are clipped in chronological order rather than added twice; this conservative choice can undercount an ambiguous app.
- Resolves categories through `CategoryCatalog`; domain, surface, and rule ID are nil. Imported use is not retroactively classified as distracting, and does not invent rule opens or interventions.
- Inserts segments and a persistent `history_imports` marker in one SQLite transaction. Concurrent/repeated imports cannot duplicate history. Empty or failed imports do not consume the marker. Deleting/pruning history leaves the marker intact, so import remains one-time for that Screentime++ database.
- Does not offer a Biome fallback. The readable, sufficiently understood Knowledge interval source is used; a changed/missing schema fails visibly without inserting data or marking completion.

## Permission and reliability limits

Knowledge and restricted Biome data are protected by macOS privacy controls. The development shell could read them, but that does **not** establish that the packaged app has permission. If access is denied, add Screentime++ under **System Settings → Privacy & Security → Full Disk Access**, then quit and reopen it. The settings section links there and explains that permission can be removed after import. Missing/changed data can also cause a failure; Full Disk Access does not restore missing history.

These are private, unsupported Apple stores, not a public Screen Time export API. Schema, retention, collection, synchronized-device metadata, timestamp semantics, and coverage can change. The observed app stream stopped twelve days before investigation despite other streams being current. The app explicitly warns about incomplete coverage before the irreversible one-time import. An import does not recreate Apple's website accounting, device aggregation, idle exclusions, or Screen Time totals.

Biome's SEGB container and protobuf event payloads need version-aware parsing, deleted/tombstone handling, app focus transition pairing, and local/remote provenance. File/container timestamps alone are not reliable usage intervals. No guessed decoder or fake import is shipped.

## Research references

- Sarah Edwards's [APOLLO Knowledge app-usage module](https://github.com/mac4n6/APOLLO/blob/master/modules/knowledge_app_usage.txt) documents the stream, bundle identifier, source-device join, and 2001 epoch conversion. The implementation uses the observed field meanings, not a vendored APOLLO parser.
- [mac_apt Biome parser](https://github.com/ydkhatri/mac_apt/blob/master/plugins/biome.py) is a reference for SEGB/protobuf and App.InFocus transition research, not an Apple-supported interface.
- [screentime-archive](https://github.com/tobias-x/screentime-archive) discusses the split between local Knowledge history and Biome data on recent macOS.

## Per-app idle policy

Settings → General → Idle supports bundle-ID overrides: **Always counts as use** or **Idle after N minutes**. Overrides replace both the global input timeout and the display-sleep assertion exception. Without an override, an assertion that keeps the display awake still counts as use. Overrides apply only while the app is frontmost; a sleeping, locked, or inactive user session remains away. Existing configuration files decode with no overrides.
