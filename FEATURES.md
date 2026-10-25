# PDF Nova — Full Feature Reference

> **Fully offline PDF toolkit for Android & iOS, built with Flutter.**
> Every operation runs on the device. No file is ever uploaded.

| | |
|---|---|
| App name | PDF Nova |
| Package / bundle ID | `com.kalainova.pdf` |
| Version | 1.0.0 (build 1) |
| Platforms | Android (primary), iOS (Scan tool hidden) |
| Framework | Flutter (Dart SDK ≥ 3.3) |
| Tool count | **26 tools** in 5 sections (25 on iOS) |
| Network use | None for documents. Only the local WiFi Share server opens a socket, and it stays on the LAN. |

---

## Table of contents

1. [Tool catalogue at a glance](#1-tool-catalogue-at-a-glance)
2. [Organize tools](#2-organize-tools)
3. [Shrink & convert tools](#3-shrink--convert-tools)
4. [Secure tools](#4-secure-tools)
5. [Smart tools](#5-smart-tools)
6. [More tools](#6-more-tools)
7. [Home screen, recents & file handling](#7-home-screen-recents--file-handling)
8. [Android home-screen widgets & shortcuts](#8-android-home-screen-widgets--shortcuts)
9. [Design system & motion](#9-design-system--motion)
10. [Architecture](#10-architecture)
11. [Tech stack](#11-tech-stack)
12. [Storage locations](#12-storage-locations)
13. [Permissions](#13-permissions)
14. [Monetization (ads)](#14-monetization-ads)
15. [Limits & known gaps](#15-limits--known-gaps)
16. [Build & run](#16-build--run)

---

## 1. Tool catalogue at a glance

| Section | Tool | What it does | Flow | Output |
|---|---|---|---|---|
| **Organize** | Merge | Combine 2+ PDFs into one | Generic | `.pdf` |
| | Split | Extract a page range | Generic | `.pdf` |
| | Pages | Reorder, rotate, delete pages | Custom | `.pdf` |
| | Batch | Run one action on many PDFs | Custom | many `.pdf` |
| **Shrink & convert** | Compress | Smart size reduction | Generic | `.pdf` |
| | Fit to size | Guarantee a target file size | Generic | `.pdf` |
| | Images → PDF | Photos into one PDF | Generic | `.pdf` |
| | PDF → Images | Every page as a JPEG | Generic | many `.jpg` |
| | PDF → Text | Extract all text (OCR fallback) | Generic | `.txt` |
| | PDF → Word | Export to `.docx` | Generic | `.docx` |
| | Word → PDF | Convert `.docx` to PDF | Generic | `.pdf` |
| | PDF → PPT | Each page as a slide | Generic | `.pptx` |
| **Secure** | Unlock | Remove password (Aadhaar or manual) | Generic | `.pdf` |
| | Protect | Add an AES-256 password | Generic | `.pdf` |
| | Watermark | Diagonal text on every page | Generic | `.pdf` |
| | Clean metadata | Strip author, title, history | Generic | `.pdf` |
| | Vault | Biometric-locked private folder | Custom | — |
| **Smart** | Scan *(Android only)* | Camera → clean multi-page PDF | Custom | `.pdf` |
| | OCR | Read text from scanned pages | Generic | `.txt` |
| | Sign | Draw and place a signature | Custom | `.pdf` |
| | Fill form | Type into PDF form fields | Custom | `.pdf` |
| | Quick Notes | Write a note, save as PDF | Custom | `.pdf` |
| **More** | Page numbers | Stamp "1 / N" on every page | Generic | `.pdf` |
| | Stamp | PAID / APPROVED / custom stamp | Generic | `.pdf` |
| | Reader | Viewer with night mode + read-aloud | Custom | — |
| | WiFi share | Phone-to-phone transfer, no internet | Custom | — |

**Generic** tools share one screen: *pick file → set options → processing → success*.
**Custom** tools have their own screen but reuse the same processing and success views.

Tool registry: [lib/features/home/tools.dart](lib/features/home/tools.dart)

---

## 2. Organize tools

### Merge
- Pick **two or more** PDFs. Re-picking adds to the list; each file can be removed individually.
- Pages are copied in pick order, keeping each page's original size.
- Output: `merged_<timestamp>.pdf`

### Split
- Pick one PDF, enter **From page** and **To page**.
- Out-of-range values are clamped to the document (e.g. "To 999" stops at the last page).
- Output: `split_<from>_<to>_<timestamp>.pdf`

### Pages (Organize)
Screen: [lib/features/organize/organize_screen.dart](lib/features/organize/organize_screen.dart)
- Renders a thumbnail of every page once (PDFium, 0.7× scale).
- **Long-press and drag** to reorder (lifted card scales to 1.04×).
- **Rotate** button turns a page 90° clockwise (cycles 0° → 90° → 180° → 270°).
- **Delete** button removes a page.
- Encrypted or corrupt PDFs show an error instead of an endless spinner.
- Output: `organized_<timestamp>.pdf`

### Batch
Screen: [lib/features/batch/batch_screen.dart](lib/features/batch/batch_screen.dart)
- Pick many PDFs, choose **one** action, run it on all of them:
  - Compress
  - Protect (asks for a password)
  - Watermark (asks for text)
  - Clean metadata
- The success screen lists every output with **Share all**.

---

## 3. Shrink & convert tools

### Compress (smart, two-pass)
Runs on a background isolate so the progress ring never freezes.
1. **Lossless pass** — Syncfusion stream compression at the best level. Text stays selectable.
2. If that saves **less than 20%** (typical for scanned or image-heavy PDFs), a **lossy pass** renders pages at 1.5× and re-encodes them as JPEG (quality 82).
3. Whichever result is **smaller** is kept.

### Fit to size (guaranteed size)
- Target slider from **50 KB to 5 MB**, plus presets: 100 KB · 200 KB · 500 KB · 1 MB · 2 MB · 5 MB.
- Shows the original size and an estimated "~N% smaller" badge.
- Steps down through six render scale / JPEG quality pairs (2.0×/80 → 0.7×/30) until the pages fit within 92% of the target (8% headroom for PDF structure).
- If nothing fits, it returns a best-effort file at 0.7× / quality 25 (`fit_best_effort_…`).
- The UI states clearly that output is image-based: text can no longer be selected. Built for government and job portal upload limits.

### Images → PDF
- Pick photos from the gallery; thumbnails show with remove buttons. Re-picking appends.
- Each image is placed on an **A4 page** (portrait or landscape to match the image), scaled to fit and centred, aspect ratio preserved.
- Images are re-encoded to JPEG (quality 88).

### PDF → Images
- Renders every page at 2× (~144 dpi), composites onto white (no black transparent areas), saves as JPEG (quality 92).
- Output folder: `PDFNova/images_<timestamp>/page_1.jpg …`

### PDF → Text
- Extracts the text layer with Syncfusion.
- If fewer than 10 characters come back (a scanned PDF), it **falls back to OCR** automatically.
- Output: `extracted_<timestamp>.txt`

### PDF → Word (.docx)
Service: [lib/services/conversion_service.dart](lib/services/conversion_service.dart)
- Builds a real `.docx` (OpenXML zip) entirely offline.
- For **each page**:
  - a high-resolution **image of the page** (1.8×, JPEG 90) so layout and pictures are preserved, followed by
  - the page's **editable text**, line by line, with **centre and right alignment detected** from line positions.
- **Scanned PDFs** (under ~15 characters per page) are OCR'd first so the Word file still has editable text.
- Page breaks between pages.

### Word → PDF
- Reads paragraphs from `word/document.xml` in the `.docx`.
- Lays them out on PDF pages in Helvetica 12 pt with word wrap, 60 pt margins and automatic page breaks.
- Smart quotes, dashes, bullets, ™ © ® are converted to safe equivalents.

### PDF → PPT (.pptx)
- Renders each page (1.5×, JPEG 90) and places it as a full-slide picture in a valid `.pptx` (4:3 slides).
- Opens in the built-in [PPT viewer](#built-in-pptx-viewer) as well as PowerPoint, Google Slides or WPS.

---

## 4. Secure tools

### Unlock
Two modes, switchable with a segmented control:

| Mode | Input | How |
|---|---|---|
| **Aadhaar** | Name as on Aadhaar + year of birth | Builds the e-Aadhaar password automatically: first 4 letters of the name in capitals + birth year (e.g. `RAVI1990`). |
| **I know the password** | Password | Uses it as given. |

- Both user and owner passwords are cleared in the output.
- A wrong password gives a friendly message: *"That password did not open this PDF. Check the name spelling and year…"*
- Output: `unlocked_<timestamp>.pdf`

### Protect
- Adds a user password (minimum 4 characters) with **AES-256** encryption.
- Output: `protected_<timestamp>.pdf`

### Watermark
- Any text (e.g. CONFIDENTIAL), drawn **diagonally (−40°)** across the centre of every page.
- Helvetica Bold 48 pt, grey, 25% opacity.

### Clean metadata
- Clears author, title, subject, keywords, creator and producer, removes the modification date, and rewrites the file without incremental updates so earlier revisions are gone.
- Output: `clean_<timestamp>.pdf`

### Vault
Screen: [lib/features/vault/vault_screen.dart](lib/features/vault/vault_screen.dart)
- A private folder inside app storage (`PDFNovaVault/`) that other apps cannot browse.
- **Unlock with fingerprint, face, or device PIN/pattern** (`local_auth`, biometric-only off so device credentials work as a fallback).
- **Fails closed**: if the device has no biometric and no screen lock, the vault stays locked and explains how to set one up.
- Once unlocked: list files, open a file, delete a file, add a PDF.

---

## 5. Smart tools

### Scan (Android only)
Screen: [lib/features/scan/scan_screen.dart](lib/features/scan/scan_screen.dart)
- Launches Google's **ML Kit Document Scanner** on device:
  - automatic edge detection and perspective correction
  - cleanup filters
  - up to **50 pages** per scan
  - import from gallery as well as camera
- The resulting PDF is copied into the PDF Nova output folder.
- Cancelling shows a "Scan cancelled — Try again" screen, never a stuck spinner.
- Hidden from the grid on iOS automatically.

### OCR
Service: [lib/services/ocr_service.dart](lib/services/ocr_service.dart)
- Renders each page at 2× and runs **ML Kit Text Recognition** on device.
- **English (Latin) first**; if a page yields under 8 characters, a **Devanagari** pass runs (Hindi, Marathi, etc.) and the better result wins.
- Output `.txt` has page markers (`───── Page 1 ─────`).
- If nothing is recognised: *"No readable text was found in this PDF."*

### Sign
Screen: [lib/features/signature/signature_screen.dart](lib/features/signature/signature_screen.dart)
Three stages:
1. **Draw** the signature on a pad (dark ink pen). Clear and redraw as needed.
2. **Choose the PDF** to sign.
3. **Position** on a live page preview: pick the page, drag the signature, resize with a slider.
- Preview coordinates map **1:1** to the PDF (relative centre + relative width), so it lands exactly where it was shown.
- Output: `signed_<timestamp>.pdf`

### Fill form
Screen: [lib/features/formfill/formfill_screen.dart](lib/features/formfill/formfill_screen.dart)
- Lists every **text field** in the PDF's AcroForm with its current value, one input per field.
- **"Lock after filling"** toggle (on by default) flattens the form so values become permanent print.
- Output: `filled_<timestamp>.pdf`

### Quick Notes
Screen: [lib/features/notes/notes_screen.dart](lib/features/notes/notes_screen.dart)
- Title and body editor.
- **Save as PDF**: title (22 pt bold), timestamp line, divider, then the body with automatic pagination for long notes.
- Saved notes appear under the **Notes** folder in Recents, with an **Open** action in the snackbar.
- On Android, pinning this tool to the home screen adds the [Quick Note widget](#quick-note-widget).

---

## 6. More tools

### Page numbers
- Adds **"1 / N"** at the bottom centre of every page (Helvetica 11 pt, dim grey).

### Stamp
- Custom text (auto-uppercased), e.g. PAID, APPROVED, REJECTED.
- Four colour choices: red, green, violet, cyan.
- Drawn in the **top-right corner of every page**, bold 26 pt, tilted −12°, with a rectangular border, 85% opacity.

### Reader
Screen: [lib/features/viewer/viewer_screen.dart](lib/features/viewer/viewer_screen.dart)
- PDFium-rendered viewer with **pinch-to-zoom** and page tracking.
- **Night mode**: colour-inverting filter for dark reading.
- **Read aloud** (text-to-speech) for the current page:
  - Uses the page's text layer; **OCR fallback** for scanned pages.
  - **Automatic language detection** by script: Tamil, Hindi, Telugu, Malayalam, Kannada, Bengali, Gujarati, Arabic, Chinese, Japanese, Russian, Spanish, default English (India).
  - Manual language picker: Auto, Tamil, Hindi, English (India), English (US), Telugu, Malayalam, Kannada, Spanish, French.
  - Prefers Google TTS on Android and picks a matching installed voice.
  - Adjustable reading speed (natural default ≈ 1.0×).
- No ads in the Reader.

### WiFi share
Screen: [lib/features/wifishare/wifishare_screen.dart](lib/features/wifishare/wifishare_screen.dart) · Service: [lib/services/wifi_share_service.dart](lib/services/wifi_share_service.dart)
- Starts a tiny HTTP server on the phone (`dart:io`) serving **one file**.
- Shows a **QR code** and URL; the other device opens it in **any browser** — no app needed, **no internet needed**, works over a **mobile hotspot**.
- Picks the right network interface: prefers WiFi/hotspot/ethernet/USB tethering and skips cellular and VPN addresses that another phone could never reach.
- Tries ports **8765–8770** if one is busy.
- Serves only the shared file (everything else returns 404) and sends a correct download filename, including names with spaces or non-ASCII characters.
- **Stop sharing** shuts the server down.

---

## 7. Home screen, recents & file handling

### App frame — three tabs
Shell: [lib/features/home/home_shell.dart](lib/features/home/home_shell.dart)

| Tab | What it holds |
|---|---|
| **Tools** | Artwork header ("Every document, *handled privately.*"), a search bar that pins under the status bar, and the five tool families as two-column grids. |
| **Files** | Every recent output, grouped **by tool** (one folder per tool actually used) or as a flat **All files** list. |
| **Settings** | Theme (Auto / Light / Dark), Reduce motion, a plain-language privacy summary, open-source licences. |

- Back on Files or Settings returns to Tools before leaving the app.
- **Search** filters all tools live by name or description, with a friendly empty state.
- **Long-press a tool card** (Android) → *Add to Home Screen* dialog → pins a launcher shortcut for that tool (Android 8+). See [section 8](#8-android-home-screen-widgets--shortcuts).

### Files tab
Screen: [lib/features/files/files_tab.dart](lib/features/files/files_tab.dart)
- Last **20 outputs** are remembered (Hive).
- **By tool**: folder cards with the tool's tinted icon, file count and "Latest 2h ago". Tapping one grows it into the [folder screen](lib/features/files/folder_screen.dart).
- **All files**: rows showing file type, name, "Tool · time ago · size".
- Each row's **⋯ menu** opens a sheet: Open · Share · Save to Downloads · Delete (with confirmation). Deleting also removes it from Recents.
- Files that no longer exist on the phone say so, and can be removed from the list.
- Empty state with a "Browse tools" shortcut.

### Success screen
View: [lib/features/tool/success_view.dart](lib/features/tool/success_view.dart)
- Animated check mark, file card with size.
- **Open File**: `.pptx` opens in the built-in viewer, everything else in the system app.
- **Save File** → copies to the public **`Download/PDFNova/`** folder:
  - Android 10+: via **MediaStore** (works with scoped storage, no storage permission needed).
  - Android 9 and below: direct write plus a media scan.
  - If something fails, it falls back to app-specific external storage and says where the file went. It never fails silently.
- **Share** through the system share sheet ("Made with PDF Nova").
- Multi-output tools (Batch, PDF → Images) list every file with **Share all**.

### Built-in .pptx viewer
Screen: [lib/features/viewer/ppt_viewer_screen.dart](lib/features/viewer/ppt_viewer_screen.dart)
- Opens `.pptx` files **without PowerPoint or WPS installed**.
- Slides made by PDF Nova show as full images with pinch-to-zoom; decks made elsewhere fall back to each slide's extracted text.
- Previous/next navigation, "Slide N of M", and save to Downloads.

### Processing view
- Thin progress ring with a tool-specific label (e.g. "Building your Word document", "Squeezing to size").
- "Processing on your phone — nothing leaves it."
- Progress eases toward 90% while the real work runs, then snaps to 100% when it finishes. The wait shown is always the real wait.
- Back button and back gesture are blocked during processing so work is never abandoned halfway.

### Error messages
Friendly, specific messages instead of stack traces:
- Wrong password → check the name spelling and year.
- No text found → "No readable text was found in this PDF."
- Anything else → "The file may be corrupted — try another copy."

---

## 8. Android home-screen widgets & shortcuts

Native Kotlin code: [android/app/src/main/kotlin/com/kalainova/pdf/](android/app/src/main/kotlin/com/kalainova/pdf/)

| Widget | Size | Buttons |
|---|---|---|
| **PDF Nova Studio** | 4×2 (resizable) | Merge · Split · Compress · Scan · Notes · Word |
| **PDF Nova Quick** | 2×2 (resizable) | Scan · Notes · Merge · Word |
| **PDF Nova Quick Note** | 3×2 (resizable) | Shows the saved note text |

### Tool widgets
- Each button opens the app **directly into that tool**, using the `toolId` intent extra and the `pdfnova/widget_shortcut` method channel.
- Works on cold start (`getInitialShortcut`) and when the app is already running (`onShortcutLaunched`).

### Quick Note widget
- Shows the current note on the home screen ("Tap to write a note…" when empty).
- Tapping opens a **lightweight popup editor** over the launcher (not the full app). **Save** updates every placed Notes widget instantly.
- Text is stored in Android SharedPreferences.

### Launcher shortcuts
- **Static** (long-press the app icon): Merge, Scan, Notes, PDF → Word.
- **Pinned** (long-press a tool card in the app): any tool can be pinned as a home-screen shortcut with a generated violet-to-cyan icon showing the tool's initials. Pinning *Quick Notes* places the real Quick Note widget instead of an icon.

---

## 9. Design system & motion

### "Folio" — a minimal, paper-like design language
Tokens: [lib/core/theme/app_colors.dart](lib/core/theme/app_colors.dart) · Theme: [lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart)

- **Solid surfaces, no glass.** Warm paper canvas, white cards with hairline borders instead of shadows or blur.
- **One accent** (cobalt) for actions. Each tool family gets a quiet tint so sections are recognisable at a glance.
- **Light and dark** themes with the same layout. Follows the phone by default; can be forced in Settings. Switching cross-fades every colour.
- **Background artwork**: original generated abstract art (soft colour fields with paper grain), one per theme, in `assets/images/`. Used full-screen on the splash and as the home header.
- **Type**: *Instrument Serif* for display moments (hero lines, screen titles, big numbers), *Inter* for everything you read or tap. Both are **bundled** in `assets/fonts/` (SIL OFL, licences shown in-app), so the app looks the same offline.
- **Logo mark**: a page with a folded corner and a four-point star, drawn in code ([nova_mark.dart](lib/core/widgets/nova_mark.dart)) and used as the Android launcher/adaptive icon.

| Token | Light | Dark | Use |
|---|---|---|---|
| Canvas | `#F4F1EB` | `#101012` | Page background |
| Surface | `#FFFFFF` | `#1A1A1D` | Cards, sheets, tab bar |
| Surface alt | `#ECE8E0` | `#242428` | Fields, tracks |
| Border | `#E4DFD5` | `#2A2A2F` | Hairlines |
| Ink | `#16161A` | `#F3F1EC` | Primary text |
| Accent | `#3550E6` | `#7C8FFF` | Actions, focus |
| Success / Danger | `#17915A` / `#D63B2F` | `#5CD69A` / `#FF7A6E` | States |

Tool-family tints: Organize = cobalt, Shrink & convert = amber, Secure = green, Smart = violet, More = rose.

Components in [lib/core/widgets/](lib/core/widgets/): `NovaCard`, `Pressable`, `NovaButton` (primary / secondary / quiet), `NovaField`, `NovaSegmented`, `NovaChip`, `NovaIconTile`, `NovaEyebrow`, `NovaIconButton`, `NovaProgress`, `NovaArt`, `NovaMark`, `showNovaDialog`, `showNovaSheet`. Tool screens share `ToolHeader`, `PickZone` (dashed drop zone), `ToolStages` and `ToolActionBar` in [lib/features/tool/](lib/features/tool/).

### Motion
All transitions share one curve family ([app_motion.dart](lib/core/theme/app_motion.dart)): things arrive fast and settle slowly (Material "emphasized"), and leave quickly.

| Moment | Transition |
|---|---|
| **App launch** | Android launch screen shows the mark on the canvas colour (no white/black flash). Splash: artwork settles from a slow 1.12× zoom, the mark **draws itself** (outline → fold → star blooms), "PDF Nova" rises out of a mask, the tagline fades in. Tap to skip. |
| **Splash → Home** | The artwork **flies (Hero)** from full screen into the home header while home fades in; header lines and cards rise into place in a stagger. |
| **Open / close a tool** | **Container transform**: the tapped card grows into the full tool screen and shrinks back into the same card on close. Same for Files folders. |
| **Changing tabs** | **Shared-axis slide** that follows direction (right tab → content slides left). The tab pill glides between items; icons switch outline → filled with a spring. |
| **Other screens** (Android) | Parallax push: new page slides in from the right while the one behind drifts left and dims. iOS keeps the native swipe-back transition. |
| **Tool stages** | Input → processing → success **fade-through**. Signature steps slide sideways with a 3-step progress bar. |
| **Dialogs / sheets** | Dialogs rise and scale up from 92% over a scrim; sheets glide up on the same curve. |
| **Processing** | Thin progress ring with a serif percentage; a soft comet travels the unfinished track. |
| **Success** | Ring pops open with a fading pulse, then the check mark draws itself. |
| **Details** | Cards and buttons press in with a spring; segmented controls slide their thumb; page rotation in *Pages* turns smoothly; Reader night mode fades between normal and inverted; artwork has scroll parallax and stretches on overscroll; theme changes cross-fade. |

**Reduce motion**: when the phone asks for less motion, or the Settings toggle is on, transitions become short fades and entrance animations are skipped.

## 10. Architecture

```
lib/
├── main.dart, app.dart          Entry, font licences, Hive init, light/dark MaterialApp
├── core/
│   ├── theme/                   NovaColors tokens, ThemeData, motion tokens, page transitions
│   ├── utils/file_open.dart     Opens .pptx in-app, everything else via system
│   └── widgets/                 Nova design-system components (cards, buttons, fields, art, mark…)
├── services/                    All work happens here — no UI
│   ├── pdf_service.dart         Syncfusion document surgery (merge…forms)
│   ├── conversion_service.dart  PDF→Word, Word→PDF, PDF→PPT (OpenXML by hand)
│   ├── raster_service.dart      PDFium page rendering (pdfx)
│   ├── ocr_service.dart         ML Kit text recognition
│   ├── pptx_reader.dart         Minimal .pptx parser for the viewer
│   ├── file_service.dart        Pick, open, share, save to Downloads
│   ├── wifi_share_service.dart  Local HTTP server
│   ├── storage_service.dart     Hive: recents, counters, theme + reduce-motion prefs
│   ├── shortcut_service.dart    Android widget/shortcut channel
│   └── ad_service.dart          Stub (ads disabled)
└── features/
    ├── splash/                        Animated launch
    ├── home/                          Shell + tab bar, Tools tab, tool cards, tool router
    ├── files/  settings/              Files and Settings tabs
    ├── tool/                          Generic tool journey + shared tool-screen pieces
    └── organize/ batch/ scan/ signature/ formfill/ notes/
        viewer/ vault/ wifishare/      Custom-flow tools
```

### Key patterns
- **One generic `ToolBloc`** ([tool_bloc.dart](lib/features/tool/tool_bloc.dart)) runs any task that returns a list of output paths. States: `Idle → Processing(progress) → Success(paths) | Failure(message)`. On success it records the recent and increments the operation counter.
- **Services are singletons** (`PdfService.instance`, …) and stay free of UI so they can be tested.
- **Heavy CPU work runs off the UI thread**: Compress and Fit to size run in `Isolate.run`, with platform channels re-attached through `RootIsolateToken`.
- **Two PDF engines, each for what it does best**:
  - *Syncfusion* — editing documents (merge, encrypt, draw, forms, text extraction).
  - *PDFium (pdfx)* — rendering pixels (thumbnails, previews, rasterising, OCR input).
- **Native bridges** (Kotlin, `MainActivity`):
  - `pdfnova/widget_shortcut` — pin shortcut or widget, get the launch tool.
  - `pdfnova/downloads` — MediaStore save to `Download/PDFNova`.

---

## 11. Tech stack

| Area | Package |
|---|---|
| State | `flutter_bloc`, `equatable` |
| PDF editing | `syncfusion_flutter_pdf` (Community License) |
| PDF rendering | `pdfx` (PDFium) |
| Imaging | `image` |
| Office files | `archive` (hand-built DOCX/PPTX zips) |
| OCR & scanning | `google_mlkit_text_recognition`, `google_mlkit_document_scanner` |
| Storage | `hive`, `hive_flutter`, `path_provider` |
| Files | `file_picker`, `image_picker`, `open_filex`, `share_plus` |
| Signature | `signature` |
| Biometrics | `local_auth` |
| Speech | `flutter_tts` |
| QR | `qr_flutter` |
| UI & motion | `flutter_animate` (entrances), `animations` (container transform, shared axis, fade-through) |
| Fonts | Inter + Instrument Serif, bundled as assets (no runtime download) |

---

## 12. Storage locations

| What | Where |
|---|---|
| Tool outputs | `<app documents>/PDFNova/<name>_<timestamp>.<ext>` |
| PDF → Images | `<app documents>/PDFNova/images_<timestamp>/page_N.jpg` |
| Notes PDFs | `<app documents>/<Title>_Note_<timestamp>.pdf` |
| Vault | `<app documents>/PDFNovaVault/` |
| Saved by the user | `Download/PDFNova/` (public, Android) |
| Recents, counters, theme | Hive boxes `recents` (last 20) and `settings` (incl. theme mode, reduce motion) |
| Quick Note widget text | Android SharedPreferences `notes_widget_prefs` |

---

## 13. Permissions

**Android** ([AndroidManifest.xml](android/app/src/main/AndroidManifest.xml))

| Permission | Why |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | WiFi Share local server (and AdMob when re-enabled) |
| `USE_BIOMETRIC`, `USE_FINGERPRINT` | Vault unlock |
| `WRITE_EXTERNAL_STORAGE` (max SDK 29) | Save to Downloads on Android 9 and below only |

No camera or storage permission is requested: the ML Kit scanner and system file picker handle their own access.

---

## 14. Monetization (ads)

**Currently disabled for release.** `google_mobile_ads` is removed from `pubspec.yaml`, and `AdService` / `AdBannerStrip` are no-op stubs.

The re-enable plan is marked in code with `ADS DISABLED FOR RELEASE` comments (in `main.dart`, `home_screen.dart`, `tool_screen.dart`, `processing_view.dart`, `success_view.dart` and the manifest). The intended policy-safe design:
- **Banner** in a fixed-height strip on Home, so content never jumps when an ad loads.
- **Interstitial** at most once per 3 completed operations (counter already tracked in Hive).
- **Rewarded** gate on Save/Share, with a guaranteed fallback if no ad fills.
- **No ads** in the Reader or Vault.

---

## 15. Limits & known gaps

### By design
- **Fit to size** and the lossy **Compress** pass produce image-based PDFs; text is no longer selectable. The UI says so.
- **PDF → Word** puts a picture of each page *and* its editable text in the document, so the content appears twice per page. Layout-perfect, fully editable conversion is not possible offline.
- **Word → PDF** keeps paragraph text only (no images, tables, fonts or styling).
- **Syncfusion Community License** is free under US$1M revenue and ≤5 developers. Recheck before scaling.

### Gaps found in the current code
- **Word → PDF drops non-Latin text.** Characters outside Latin-1 (Tamil, Hindi, etc.) are replaced with spaces because it uses the built-in Helvetica font. Embedding a Unicode TrueType font would fix this.
- **PDF → PPT stretches pages.** Portrait A4 pages are stretched to fill 4:3 landscape slides instead of being letterboxed.
- **Vault is not encrypted.** Files are protected by app-private storage and the biometric gate only; on a rooted device or through a backup they are readable.
- **Two separate "notes".** The in-app Quick Notes screen (saves PDFs) and the home-screen Quick Note widget (SharedPreferences text) do not share data.
- **Notes PDFs are saved outside the `PDFNova/` output folder**, unlike every other tool.
- **Split** supports one range per run (no "1-3, 7, 9-12").
- **iOS `Info.plist`** is missing `NSFaceIDUsageDescription`, which Vault needs on Face ID devices.
- **Unused Android resources**: `pdfnova_widget_info.xml`, `pdfnova_widget_layout.xml` and `pdfnova_widget_2x1.xml` are not registered in the manifest.
- **iOS app icon** is still the Flutter default (the Android launcher icon uses the new mark).
- **Tests**: [test/widget_test.dart](test/widget_test.dart) is a placeholder; no real unit or widget tests yet.
- **README is out of date**: it lists 22 tools and says PDF ↔ Word is not possible offline.

---

## 16. Build & run

```bash
flutter pub get
flutter run                 # debug on a connected device
flutter build apk --release # Android release APK
flutter build appbundle     # Play Store bundle
```

- **Release signing**: put credentials in `android/key.properties` (gitignored): `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Without it, release builds fall back to debug signing.
- **Android**: `MainActivity` already extends `FlutterFragmentActivity` (required by `local_auth`). Java/Kotlin target 17.
- **iOS**: add `NSFaceIDUsageDescription` before shipping Vault. Scan is hidden automatically.
