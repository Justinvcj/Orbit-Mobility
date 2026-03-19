---
phase: 3.5
plan: 2
wave: 1
---

# Plan 3.5.2: HTTP Request Cancellation & Photon Tuning

## Objective
Eliminate wasted network requests by cancelling in-flight HTTP calls when the user types faster than the debounce window. Tighten Photon API to return only actionable riding destinations.

## Context
- rider_app/lib/main.dart (L389-450 search pipeline, L114 debounce timer)

## Tasks

<task type="auto">
  <name>Implement HTTP Client cancellation pattern</name>
  <files>rider_app/lib/main.dart</files>
  <action>
    1. Add `http.Client? _activeSearchClient;` to state variables near L114.
    2. In `searchAddress()` (L398), BEFORE creating the URL:
       - Call `_activeSearchClient?.close();` to abort any in-flight request.
       - Create `_activeSearchClient = http.Client();`.
    3. Replace `http.get(url, ...)` with `_activeSearchClient!.get(url, ...)`.
    4. Wrap the entire try-catch in an OUTER try-catch for `http.ClientException`:
       - On `ClientException`, silently return (this means the request was cancelled — expected behavior).
    5. In `dispose()`, add `_activeSearchClient?.close();`.
    6. Do NOT change the debounce timer duration (500ms) — cancellation handles the overlap.
  </action>
  <verify>Type "MALL" rapidly — only 1 network response processes (verify via print debug)</verify>
  <done>In-flight HTTP requests are cancelled when new input arrives</done>
</task>

<task type="auto">
  <name>Append layer filter to Photon URL</name>
  <files>rider_app/lib/main.dart</files>
  <action>
    1. In `searchAddress()` URL construction (L407), append:
       `&layer=house,street,venue,locality`
    2. This filters out broad geographic entities (states, countries, continents) that are not actionable ride destinations.
    3. Keep existing params: `&lat=11.0168&lon=76.9558&limit=5`.
  </action>
  <verify>Search "India" — should NOT return the country as a result</verify>
  <done>Photon returns only house/street/venue/locality level results</done>
</task>

## Success Criteria
- [ ] Rapid typing cancels stale HTTP requests (no zombie responses)
- [ ] Photon returns only actionable destination types
