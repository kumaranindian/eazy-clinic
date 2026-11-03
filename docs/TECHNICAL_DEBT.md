# Technical Debt and Known Limitations

| ID | Item | Impact | Plan |
|---|---|---|---|
| TD-01 | Firebase Admin SDK for Dart is not an official Google product; options must be evaluated (community package vs `googleapis` REST). Phase 0 has no Firebase dependency. | Blocks Phase 1 | Spike at the start of Phase 1; ADR. |
| TD-02 | Flutter 3.32.8 / Dart 3.8.1 are over a year old. `DropdownButtonFormField` uses `value:` (deprecated in newer Flutter in favour of `initialValue`). | Future upgrade churn | Decide upgrade before Phase 1; update `EcDropdown`. |
| TD-03 | Logo is raster with opaque white background; icon crop is derived from it. No transparent/vector master; no dark-mode variant; no Android adaptive icon (foreground/background layers). | Visual polish | Obtain vector master; regenerate assets with `scripts/sync_brand_assets.sh`. |
| TD-04 | Fonts and brand assets are duplicated (repo-level `assets/` and inside `design_system`), kept in sync by script. | Drift risk | Keep script; consider making `design_system/assets` the single source. |
| TD-05 | Three app shells duplicate ~100 lines of bootstrap (main, router provider, config provider). | Duplication | When Phase 1 adds API client + auth, extract a shared Flutter `app_core` package (needs ADR: it is not in the original monorepo proposal). |
| TD-06 | No CI. `scripts/check_all.sh` runs format, analyze and tests locally. | Regressions | Add GitHub Actions in Phase 1. |
| TD-07 | One transient Android Gradle failure was observed (not diagnosed). Docker image build and Firebase CLI were not exercised. | Unknown | Verify in CI; build the Docker image in Phase 1. |
| TD-08 | Backend: unmatched HTTP methods return 404 (not 405) because of `shelf_router` defaults; no rate limiting; no graceful in-flight request drain beyond `server.close`. | Minor | Rate limiting in Phase 1 (auth endpoints); 405 if needed. |
| TD-09 | Web build warns that `CupertinoIcons` font is not found (we deliberately did not add `cupertino_icons`). | Cosmetic warning | Ignore unless Cupertino icons are used. |
| TD-10 | UI is verified by widget tests and one reviewed gallery screenshot; the web logo render was **not** visually confirmed in a browser (headless screenshot tooling was unreliable). Asset bundling and proportions are covered by tests. | Low | Confirm manually when running `flutter run -d chrome`. |
| TD-11 | Light theme only; no dark mode or localization (English only). India market will need Hindi/regional languages. | Product | Plan i18n in Phase 1 (use `intl`/ARB). |
| TD-12 | Accessibility checked by design (contrast, 48dp targets, semantics on key widgets) but no automated a11y audit yet. | Compliance | Add in Phase 11. |
| TD-13 | Contrast: white on brand red #E92335 ≈ 4.4:1 (< 4.5:1 AA for normal text); Medical Blue on white ≈ 4.5:1. Brand colours are mandated, so this needs a design decision (e.g. use 18 sp+ bold on red, or a slightly darker red for text/buttons). | Accessibility | Decide in Phase 1 design review; audit in Phase 11. |
