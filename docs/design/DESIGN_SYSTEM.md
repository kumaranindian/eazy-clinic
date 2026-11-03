# EazyClinic Design System

Implemented in `packages/design_system` (Flutter). Import `package:design_system/design_system.dart`.
Source references: `assets/branding/original/EazyClinic Caring Healthcare Logo.png` and
`docs/design/reference/EazyClinic Healthcare App Flow Mockup (1).png`. Analysis: `UI_UX_REFERENCE_ANALYSIS.md`.

**Rule:** features use tokens and components only. No hex colours, raw font sizes, magic spacing or one-off buttons in feature code.

## 1. Colour tokens (`EcColors`)

| Token | Hex | Use |
|---|---|---|
| `navy` | #103B64 | Headings, navigation/structure, side navigation |
| `red` | #E92335 | Primary actions, brand highlight, selected-state accent |
| `blue` | #087FAF | Secondary actions, info, focus ring |
| `background` | #F8FAFC | Page background |
| `infoBackground` | #E6F3FA | Stat tiles, info banners, avatar circles |
| `surface` | #FFFFFF | Cards, dialogs, app bars |
| `textPrimary` / `textSecondary` | #1F2937 / #6B7280 | Text |
| `border` | #E5E7EB | Hairlines, card outlines, dividers |
| `success` / `warning` / `error` | #16A34A / #D97706 / #DC2626 | Semantic |
| `inputFill` | #F1F5F9 | Filled input background (derived from mockup) |
| `successBackground`, `warningBackground`, `errorBackground` | #E8F7EE, #FEF3E2, #FDECEE | Chip/banner tints (derived) |
| `disabledBackground` / `disabledForeground` | #E5E7EB / #9CA3AF | Disabled controls |

The first twelve rows are the approved palette (verified by a unit test); the *derived* tokens are Phase 0 additions for states the
mockup uses but the palette does not name. Red is for actions and accents, never large background fills.

## 2. Typography (`EcTypography`, Inter 400/500/600/700, bundled, OFL licence in `assets/fonts/inter/LICENSE.txt`)

| Style | Size/line | Weight | Use |
|---|---|---|---|
| displayLarge / display | 32/40, 28/36 | 700 | Splash, hero |
| pageTitle | 24/32 | 700 | Screen titles |
| sectionTitle | 18/26 | 600 | Section headings, dialogs |
| subsectionTitle | 16/24 | 600 | Card titles |
| bodyLarge / body / bodyStrong / bodySecondary | 16/24, 14/20 | 400/600 | Content |
| label / helper / error | 12/16 | 500/400 | Field labels, hints, errors |
| button / buttonSmall | 16/24, 14/20 | 600 | Buttons |
| tableHeader / tableCell | 12/16, 13/20 | 600/400 | Data tables |
| statValue | 24/32 | 700 | Dashboard figures |

## 3. Spacing, radii, elevation, sizes (`ec_dimensions.dart`)

- **Spacing (4-pt):** xxs 2, xs 4, sm 8, md 12, lg 16, xl 24, xxl 32, xxxl 48. Page gutter 16 (phone) / 24 (wider).
- **Radii:** sm 6, md 10 (buttons, inputs), lg 14 (cards), xl 20 (sheets, dialogs), pill.
- **Elevation:** flat by default (border + soft shadow `EcShadows.card/raised`); dialogs 6.
- **Icons:** 16 / 20 / 24 / 32 / 64.
- **Controls:** button height 48 (compact 40), input 52, min tap target 48, bottom nav 64, side nav 248 (72 collapsed), max content width 1200, max form width 440.

## 4. Breakpoints (`EcBreakpoints`, `EcWindowSize`)

compact < 600 · medium 600–1023 · expanded 1024–1439 · large ≥ 1440. Layout branches on window size, never on platform.

## 5. Components

| Component | Notes |
|---|---|
| `EcPrimaryButton` / `EcSecondaryButton` | Red filled / blue outline; `isLoading`, disabled (`onPressed: null`), optional icon, `compact` |
| `EcTextField`, `EcPasswordField`, `EcSearchField` | Filled inputs, leading icon, validators plug into `Form`; password toggle; search with clear |
| `EcDropdown<T>`, `EcDateField` | Same styling; date opens Material picker |
| `EcCard`, `EcStatTile` | Bordered rounded surface; pale-blue stat tile |
| `showEcConfirmDialog`, `showEcBottomSheet` | Confirm (with `destructive`), modal sheet with safe-area/keyboard padding |
| `EcStatusChip` (+ `EcStatusTone`) | success/warning/error/info/neutral tinted pills |
| `EcLoadingIndicator`, `EcEmptyState`, `EcErrorState` | State placeholders (error has retry) |
| `EcAppBar` | White, navy title, hairline border, optional back |
| `EcNavScaffold` + `EcNavDestination` | Bottom bar on phones (red selected), navy side nav on wide windows with red selected edge; routing stays in the app |
| `EcResponsiveContainer`, `EcBreakpointBuilder` | Centered, width-capped, gutter-aware content |
| `EcBrandLogo.full / .icon` | Original artwork, `BoxFit.contain`, semantic label; never stretch |
| `DesignSystemGallery` | Dev-only showcase at `/design-system` (not routed in production) |

State coverage: loading, empty, error, success (snackbar via theme), disabled, focus/validation (input theme).

## 6. Logo usage

- Use `EcBrandLogo`; never recreate it with text/shapes, recolour, rotate or stretch.
- Clear space ≥ ¼ of logo height; minimum height 32 dp (icon) / 56 dp (full).
- The artwork has an opaque white background: place it on white or very light surfaces (inside a white tile on the navy side nav).
- Icon-only variant for app icons and collapsed navigation. Web favicon/PWA and Android launcher icons were generated from the icon variant on a white square.

## 7. Accessibility

Primary and secondary text on white ≥ 4.5:1. **Known gap:** white text on the approved red #E92335 is ≈ 4.4:1, just under WCAG AA (4.5:1) for normal-size text (it passes for large text); the approved brand red is kept, so button labels use 16 sp semibold, and this is tracked for the Phase 11 accessibility audit. Medical Blue #087FAF on white is ≈ 4.5:1 (borderline);
48 dp minimum targets; semantics labels on logo, loading, stat tiles, nav items; status never conveyed by colour alone (chips carry text).

## 8. Adding or changing components

1. Check the gallery and existing components first (CLAUDE.md §19.12).
2. Add tokens before one-off values; add the component to the gallery; add a widget test.
3. Update this document.
