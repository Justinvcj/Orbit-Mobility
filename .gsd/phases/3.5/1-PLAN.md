---
phase: 3.5
plan: 1
wave: 1
---

# Plan 3.5.1: Local Cache — Recent Searches

## Objective
Implement a "zero-latency" recent searches cache so the search screen loads instantly with history instead of a blank slate. Uses SharedPreferences (already in pubspec) to persist last 5 drop destinations.

## Context
- .gsd/ARCHITECTURE.md
- rider_app/lib/main.dart (L103-130 state vars, L452-480 selectLocation, L964-1013 search UI)
- rider_app/pubspec.yaml (shared_preferences already present)

## Tasks

<task type="auto">
  <name>Add _recentSearches state variable and loader</name>
  <files>rider_app/lib/main.dart</files>
  <action>
    1. Add `List<Map<String, String>> _recentSearches = [];` to state variables near L111.
    2. In `initState()`, call a new method `_loadRecentSearches()`.
    3. Implement `_loadRecentSearches()`:
       - Read `recent_searches` key from SharedPreferences.
       - JSON decode it into `List<Map<String, String>>`.
       - Assign to `_recentSearches` inside `setState`.
       - Wrap in try-catch; on failure, default to empty list.
    4. Do NOT alter any existing search logic — this is purely additive.
  </action>
  <verify>flutter analyze rider_app — no new errors related to _recentSearches</verify>
  <done>_recentSearches is populated from SharedPreferences on app launch</done>
</task>

<task type="auto">
  <name>Write to cache on destination select</name>
  <files>rider_app/lib/main.dart</files>
  <action>
    1. In `selectLocation()` (L452), AFTER setting the drop destination (the `else` branch at L463):
       - Build a map: `{'display_name': address, 'primary_text': address.split(',')[0], 'secondary_text': ..., 'lat': ..., 'lon': ...}`.
       - Remove any existing entry with matching lat/lon (de-duplication).
       - Insert at index 0.
       - Trim list to max 5 entries.
       - Call `_saveRecentSearches()`.
    2. Implement `_saveRecentSearches()`:
       - JSON encode `_recentSearches`.
       - Write to SharedPreferences under key `recent_searches`.
    3. Do NOT save pickup selections — only drop destinations.
  </action>
  <verify>Select a drop destination, kill app, reopen — SharedPreferences contains the entry</verify>
  <done>Drop destinations persist across app restarts, capped at 5, de-duplicated</done>
</task>

<task type="auto">
  <name>Display recent searches in UI</name>
  <files>rider_app/lib/main.dart</files>
  <action>
    1. In the search results section (L963-1013), add a NEW condition:
       - When `_searchResults.isEmpty && !_isSearching && _dropController.text.isEmpty && _recentSearches.isNotEmpty`:
       - Render a Container with "RECENT" header text and a ListView of _recentSearches using the same ListTile format as search results but with a `Icons.history` leading icon.
    2. Each ListTile `onTap` calls `selectLocation(place)` identically to live results.
    3. Maintain the existing Midnight Premium styling (0xFF1A1A1A, cyan accents).
  </action>
  <verify>Tap the Drop TextField with empty text — recent destinations appear instantly</verify>
  <done>Recent searches display immediately on focus with zero network latency</done>
</task>

## Success Criteria
- [ ] Recent searches load from SharedPreferences on app start
- [ ] Drop selections persist to cache (max 5, de-duplicated)
- [ ] Empty search bar shows recent history instantly
