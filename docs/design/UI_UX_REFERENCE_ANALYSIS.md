# UI/UX Reference Analysis

Reference: `docs/design/reference/EazyClinic Healthcare App Flow Mockup (1).png` (1312×1199, 20 phone screens, numbered 1-20).
Logo reference: `assets/branding/original/EazyClinic Caring Healthcare Logo.png`.
The mockup is a **visual direction, not a functional specification**; mock data in it (names, amounts, dates) is illustrative and sometimes internally inconsistent
(e.g. the invoice preview line items do not add to the shown total). CLAUDE.md prevails wherever they differ.

## 1. Screens in the mockup

1 Splash · 2-4 Onboarding (3) · 5 Login · 6 Sign Up · 7 Clinic Setup · 8 Doctor Dashboard · 9 Appointments List · 10 New Appointment ·
11 Patient Details · 12 Consultation · 13 Prescription · 14 Patients List · 15 Generate Bill · 16 Invoice Preview · 17 Reports · 18 Profile/Settings · 19 Patient App Login · 20 Patient App Home.

## 2. Brand analysis

Logo: red medical cross containing a white heart formed by a stethoscope (with a white plus), a navy supporting hand beneath, a red circular swoosh,
"Eazy" in navy and "Clinic" in red (rounded geometric sans), tagline "You Care. We Manage." in navy flanked by thin red rules. Message: caring (hand) + clinical
(cross/stethoscope) + management (clean structure). The mockup uses the full lockup on splash, login and invoice, a compact lockup in the doctor
dashboard header, and the icon on the clinic setup tile. Navy carries trust and structure; red carries action and urgency/care.

## 3. Colour analysis

| Observed | Mapped token |
|---|---|
| Primary CTA buttons, FAB, active tab pills, active bottom-nav item, destructive trash icons, bar-chart bars, header block on doctor dashboard | `red` #E92335 |
| Headings, titles, dark text on white | `navy` / `textPrimary` |
| Stat tiles, avatar circles, info chips ("Consultation", "New Patient") | `infoBackground` #E6F3FA + `blue` text |
| "Follow Up" status | `success` text on `successBackground` |
| Input fields | very light grey-blue fill (`inputFill`) without visible border |
| Page | white / very light grey (`background`) |

Observation: the mockup uses red more heavily than CLAUDE.md §11 intends (full red header on the doctor dashboard, red bottom-nav selection). See §11.

## 4. Typography analysis

Clean humanist/geometric sans consistent with **Inter**: bold navy screen titles (~20-24), semibold section headers, regular 12-14 body/helper text,
small grey captions, large semibold figures on stat tiles. Hierarchy relies on size/weight and navy-vs-grey, not on colour variety.
Mapped to `EcTypography` (pageTitle, sectionTitle, body, label/helper, statValue, button).

## 5. Layout analysis

- Phone frame with a 16 dp gutter; vertically stacked sections; generous whitespace; rounded cards (≈ 12-14 dp) with hairline borders/soft shadow.
- Forms: full-width fields (≈ 48-52 dp high), leading icon, placeholder text, labels above for dropdowns; full-width red submit at the bottom.
- Lists: rows with initials avatar or time on the left, name + secondary line, status text, chevron; red left accent bar on appointment rows.
- Dashboard: greeting + date, 2×2 stat tiles, 2×2 quick-action tiles with red icons, bottom navigation.
- Settings: list rows with leading icon, title, chevron; Logout as a full-width red button.

## 6. Component inventory (observed → design-system component)

| Observed | Component | Status |
|---|---|---|
| Red full-width button | `EcPrimaryButton` | Implemented |
| Outlined button ("Share", "Google", "View Details") | `EcSecondaryButton` | Implemented |
| Filled text field with leading icon | `EcTextField` | Implemented |
| Password with eye toggle | `EcPasswordField` | Implemented |
| Search field with filter icon | `EcSearchField` | Implemented (filter action: Phase 4) |
| Dropdown (role, gender, city, specialization, type) | `EcDropdown` | Implemented |
| Date/time fields | `EcDateField` (date); time picker field | Date implemented; time: Phase 5 |
| Stat tile | `EcStatTile` | Implemented |
| Card | `EcCard` | Implemented |
| Status text/pill | `EcStatusChip` | Implemented |
| Bottom navigation (4 items) | `EcNavScaffold` (compact) | Implemented |
| FAB (+) | Material `FloatingActionButton` themed red | Theme only; **TODO**: add FAB theme in Phase 5 |
| Segmented pills (Today/Tomorrow/This Week; New/Existing; Cash/UPI/Card) | `EcSegmentedControl` | **Planned** (Phase 5) |
| Underlined tabs (Overview/History/Prescriptions/Billing) | themed `TabBar` | Planned (Phase 4) |
| Avatar with initials | `EcAvatar` | Planned (Phase 4) |
| Key-value info tiles (blood group, allergies…) | `EcInfoTile` | Planned (Phase 4) |
| List row with chevron (patients, settings) | `EcListTile` | Planned (Phase 3/4) |
| Checkbox ("Remember me", terms, "send to patient") | themed `Checkbox` | Theme implemented |
| Bar chart | FL Chart wrapper `EcBarChart` | Planned (Phase 10) |
| Illustrated onboarding with page dots | `EcOnboardingPage` | Planned (Phase 8) |
| Image upload tile (clinic logo) | `EcImagePicker` | Planned (Phase 2) |
| Invoice document layout | PDF template (not a widget) | Planned (Phase 7) |
| Dialogs, bottom sheets, loading/empty/error | implemented | Implemented (not shown in mockup, required by CLAUDE.md §11) |

## 7. Mobile navigation analysis

- **Doctor app:** bottom nav Home · Patients · Appointments · More; deep screens use a back arrow app bar; primary creation via FAB or quick-action tiles.
- **Patient app:** bottom nav Home · Appointments · Reports · Profile; home quick actions: Book Appointment, My Appointments, Prescriptions, Lab Reports; "Upcoming appointment" card.
- Pattern: ≤ 5 destinations; one primary action per screen; modal flows (new appointment, prescription) are full screens with back.
- Implemented: `EcNavScaffold` (bottom bar at compact width). Routing: GoRouter `StatefulShellRoute` per app (Phase 1+).

## 8. Dashboard layout analysis and web adaptation

Mobile dashboard: greeting, stat tiles (2×2), quick actions (2×2). **Recommended responsive behaviour:**

| Window | Layout |
|---|---|
| compact | As mockup: single column, bottom nav |
| medium | Two-column cards, bottom nav or collapsed rail |
| expanded/large | Navy side navigation (collapsed at expanded < 1280 if needed, full at large), top bar with clinic/branch switcher + search + profile, 4-up stat tiles, main content + right-hand panel (today's queue / upcoming), data tables with sortable headers, filters in a toolbar, master-detail (list + patient detail side by side) |

Tables on web: sticky header, row hover, 48 dp rows, pagination from API cursor, column visibility, export where permitted.

## 9. Form design patterns

Single column; labels (floating) + helper/error text below; inline validation on user interaction (`AutovalidateMode.onUserInteraction`); primary action pinned at bottom on phones;
destructive actions behind confirm dialogs; segmented controls for 2-3 exclusive options; dropdowns for longer lists; auto-capitalisation and keyboard types (phone → numeric, email) per field;
multi-step flows (clinic setup, consultation) show progress and save drafts.

## 10. Patient experience analysis

Patient login is phone + password with Google option; home is action-first (book, appointments, prescriptions, lab reports) with the next appointment surfaced.
Needs beyond the mockup: dependent/family switcher, clinic connection/linking flow with consent, queue status screen, notifications, consent management and privacy,
empty/offline states, language selection (Indian languages), large-text support.

## 11. Conflicts and open decisions (mockup vs CLAUDE.md / security)

| # | Mockup shows | Issue | Proposed handling | Decide by |
|---|---|---|---|---|
| D-1 | Sign-up with **"Select Role: Doctor"** | Self-selecting a role is a privilege-escalation risk (CLAUDE.md §4, §5, §13). | Public sign-up creates a *clinic owner* application (clinic registration → platform approval, Module 1) or a patient account; staff/doctors join **only by invitation** (Module 5). Role dropdown removed. | Phase 1 |
| D-2 | "Continue with Google" | Not in CLAUDE.md; supported by Firebase Auth. Security/identity-proofing implications for clinical staff. | Allow for owner sign-up only if approved; always require backend membership. Patient app: decide separately. | Phase 1 |
| D-3 | Patient app **phone + password** login | Phone alone must never authorize record access (CLAUDE.md §7). | Firebase phone (OTP) auth establishes the account; **record linking** still needs clinic authorization + consent. Password optional. | Phase 8 (design in 4) |
| D-4 | Full red header on doctor dashboard; red active nav | CLAUDE.md: navy for structure/navigation, avoid excessive red backgrounds. | Navy/white header on web; red limited to action + selected-state accents (as implemented). | Phase 1 design review |
| D-5 | "Clinic Setup" right after sign-up | Clinic activation requires platform approval (Module 1). | Setup wizard allowed while `pending_approval`; no patient operations until approved. | Phase 2 |
| D-6 | "Send to Patient (SMS / Email)" on prescription | SMS/WhatsApp are future/configurable; push first (CLAUDE.md Module 19). | Show channel options only when configured; PHI never in message bodies. | Phase 6/10 |
| D-7 | Doctor dashboard lists "Billing" and "Reports" quick actions for doctors | Permissions are configurable (financial reports restricted for doctors). | Quick actions are permission-driven. | Phase 3 |
| D-8 | Patient details has Billing tab for doctor | Billing optional for doctors. | Tab hidden unless permission granted. | Phase 4/7 |
| D-9 | Reports show a single "Collections" figure on a doctor screen | Financial data restricted. | Role-aware dashboards (Module 20). | Phase 10 |
| D-10 | Currency formatting `₹ 12,450`, date `20 Oct 2026` | Needs locale handling | Use `intl` en_IN formatting. | Phase 1 |

## 12. Missing screens needed for complete workflows

See `SCREEN_INVENTORY.md` §5 (forgot/reset password, MFA, accept invitation, clinic/branch switcher, subscription/plan, queue display, check-in, patient linking, consent,
amendments, refunds, expenses, lab, documents, notifications, platform-admin console, error/offline/maintenance screens, etc.).
