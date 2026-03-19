---
phase: 3.5
plan: 3
wave: 2
---

# Plan 3.5.3: Shimmer Loaders, Empty States & Autofocus

## Objective
Replace the generic CircularProgressIndicator with premium shimmer skeleton loaders. Add an empty-state fallback for failed searches. Auto-focus the Drop TextField for instant typing.

## Context
- rider_app/pubspec.yaml (add shimmer dependency)
- rider_app/lib/main.dart (L964-970 spinner block, L948-962 Drop TextField)

## Tasks

<task type="auto">
  <name>Add shimmer package and replace spinner</name>
  <files>rider_app/pubspec.yaml, rider_app/lib/main.dart</files>
  <action>
    1. Add `shimmer: ^3.0.0` to pubspec.yaml dependencies.
    2. Run `flutter pub get`.
    3. Add `import 'package:shimmer/shimmer.dart';` to main.dart.
    4. Replace the CircularProgressIndicator block (L964-970) with a Container containing 5 shimmer ListTile placeholders:
       - Each: Shimmer.fromColors(baseColor: Color(0xFF1A1A1A), highlightColor: Color(0xFF2A2A2A))
       - Child: Row with a circular Container (40x40) and two rectangular Containers (varying width, 12-16px height) for title/subtitle.
       - Wrap in same styled Container as search results (0xFF1A1A1A bg, rounded corners).
  </action>
  <verify>Trigger a search, observe shimmer tiles instead of spinner during loading</verify>
  <done>Loading state uses 5 shimmer skeleton tiles with Midnight Premium colors</done>
</task>

<task type="auto">
  <name>Add empty state and autofocus</name>
  <files>rider_app/lib/main.dart</files>
  <action>
    1. After the search results ListView block, add a new condition:
       - `_searchResults.isEmpty && !_isSearching && _dropController.text.length >= 3 && _recentSearches.isEmpty`
       - Render a Container with:
         - Icon(Icons.location_off, color: Colors.grey, size: 48)
         - "Location not found" text in grey
         - "Try a different search term" subtitle
       - Same container styling as search results.
    2. On the Drop TextField (L951), add `autofocus: false` (we don't want keyboard to pop on initial load).
       - BUT: Add a FocusNode and request focus programmatically ONLY when user taps the search bar.
       - Actually, keep it simple: do NOT auto-pop keyboard since it covers map. Only focus on tap (current behavior is correct).
  </action>
  <verify>Search nonsense string "xyzqwerty" — "Location not found" renders cleanly</verify>
  <done>Empty state shows icon+message; keyboard behavior unchanged</done>
</task>

## Success Criteria
- [ ] Shimmer skeleton loaders replace spinner during search
- [ ] "Location not found" empty state renders for zero-result queries
