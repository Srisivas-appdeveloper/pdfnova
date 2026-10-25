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
- Extracts each page's text layer (line-based extraction — Syncfusion's plain extractor mis-decodes text after a font switch), with **on-device OCR only for pages that have no text**.
- Multi-page output has page markers (`───── Page 2 ─────`); the result notes say when OCR was used.
- Output: `extracted_<timestamp>.txt`

### PDF → Word (.docx)
Service: [lib/services/conversion_service.dart](lib/services/conversion_service.dart)
Two modes, chosen on the tool screen — **each page's content appears once** (the old version put a page picture *and* its text, duplicating everything):

| Mode | Result |
|---|---|
| **Editable text** (default) | Real paragraphs with centre/right alignment detected from line positions. Scanned pages are OCR'd. Pages with no readable text at all are added as a picture (and the result says how many). Images and exact layout are not carried over. |
| **Exact look** | Every page as a picture (keeps aspect ratio, fits the page). Looks identical; not editable. |

- The generated .docx is **re-opened and checked** (required parts, body, image links) before success is reported.

### Word → PDF
- Reads paragraphs, **headings** (Title/Heading 1–3), tabs and line breaks.
- **Unicode-correct**: Latin, Greek, Cyrillic and symbols (₹, —, “ ”) as vector text in embedded **Noto Sans**; **Tamil, Hindi/Devanagari, Telugu, Kannada, Malayalam, Bengali, Gujarati** are shaped by the device's text engine (correct vowel-sign order and conjuncts), drawn at 3× resolution, with an **invisible text layer in the matching embedded Noto font** so the PDF stays searchable and copyable.
- Scripts without a bundled font (Arabic, Hebrew, CJK, emoji…) are drawn with the phone's fonts and **reported** in the result as not searchable — never silently dropped.
- The result PDF is re-opened and checked before success.
- Verified: unit tests extract every supported script; the on-device output was rendered with poppler and Google's PDF viewer.
- Images, tables and styling from Word are not carried over (stated in the result).

### PDF → PPT (.pptx)
- Each page becomes one slide picture. **Slide size follows the first page's shape** (portrait documents get portrait slides) and every page is **letterboxed, never stretched**, on a white slide.
- The .pptx is re-opened and checked (slide and image parts) before success.
- Opens in the built-in [PPT viewer](#built-in-pptx-viewer) as well as PowerPoint, Google Slides or WPS.

---

## 4. Secure tools
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
Screen: [lib/features/vault/vault_screen.dart](lib/features/vault/vault_screen.dart) · Service: [lib/services/vault_service.dart](lib/services/vault_service.dart) · Details: [docs/SECURITY.md](docs/SECURITY.md)
- **AES-256-GCM encrypted** (authenticated), key in Android Keystore / iOS Keychain (this device only). File names are encrypted too.
- **Unlock with fingerprint, face, or device PIN/pattern**; **fails closed** with no screen lock. Re-locks when you leave the app; decrypted viewing copies live only in private temp storage and are wiped on lock.
- Tampered or damaged files are detected and kept (never auto-deleted).
- **Migration:** files from the old unencrypted vault are offered for encryption; each is verified (decrypt + checksum) before its plain copy is removed. Failures leave the original untouched.
- Excluded from Android cloud backup / device transfer (the key cannot be restored elsewhere).

---

## 5. Smart tools
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
Screen: [lib/features/notes/notes_screen.dart](lib/features/notes/notes_screen.dart) · Store: [lib/services/notes_store.dart](lib/services/notes_store.dart)
- **One quick note, shared with the Android Home-Screen widget** (same storage). Autosaves as you type, saves when the app is backgrounded, and picks up widget edits when you return.
- If the note was edited in both places at once, **both versions are kept** (merged), never overwritten.
- **Save PDF** exports title, date and body through the same Unicode-correct writer as Word → PDF, into the PDFNova folder; it appears in Files under **Notes**.
- iOS (no widget): the note is stored in the app.

---

## 6. More tools
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
Screen: [lib/features/files/files_tab.dart](lib/features/files/files_tab.dart) · Data: `StorageService.history` (single source of truth)
- **Output history** of up to **200 files** (every output of a run — e.g. all pages of PDF → Images — sharing a job id), with tool, time and size.
- **By tool**: one folder per tool actually used, with count and latest time; opens with a container transform.
- **All files**: **search by name**, **filter by type** (PDF · Word · Slides · Images · Text), **sort** (newest, oldest, name, largest).
- **Multi-select** (long-press): Share, Remove from history, Delete.
- Per-file menu: Open · Share · Save to Downloads · **Rename** (keeps extension, refuses to overwrite) · **Remove from history** (file stays) · **Delete file** (with confirmation).
- **Safety:** rename/delete only ever touch files PDF Nova created inside its own storage; anything else can only be removed from the list. Sizes are read from disk each time.
- Missing files are labelled, and **Clean up N** removes their entries in one tap.
- Old history entries (from before this version) are upgraded in place without losing any.

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
| Office files | `archive` (hand-built, re-verified DOCX/PPTX zips) |
| OCR & scanning | `google_mlkit_text_recognition`, `google_mlkit_document_scanner` |
| Encryption | `cryptography` (AES-256-GCM) + `cryptography_flutter` (native), `flutter_secure_storage` (Keystore/Keychain) |
| Storage | `hive`, `hive_flutter`, `path_provider` |
| Files | `file_picker`, `image_picker`, `open_filex`, `share_plus` |
| Signature | `signature` |
| Biometrics | `local_auth` |
| Speech | `flutter_tts` |
| QR | `qr_flutter` |
| UI & motion | `flutter_animate` (entrances), `animations` (container transform, shared axis, fade-through) |
| Fonts (bundled, SIL OFL) | Inter, Instrument Serif (UI); Noto Sans + Noto Sans Devanagari/Bengali/Gujarati/Tamil/Telugu/Kannada/Malayalam (Unicode PDF output) |
| Tests | `flutter_test`, `path_provider_platform_interface`, `plugin_platform_interface` |

## 12. Storage locations

| What | Where |
|---|---|
| Tool outputs (incl. Notes PDFs) | `<app documents>/PDFNova/<name>_<timestamp>.<ext>` (older Notes PDFs: `<app documents>/<Title>_Note_<ts>.pdf`) |
| PDF → Images | `<app documents>/PDFNova/images_<timestamp>/page_N.jpg` |
| Vault (encrypted) | `<app documents>/PDFNovaVault/<id>.nvd` + `<id>.nvm` |
| Vault viewing copies | `<temp>/vault_open/` — wiped on lock |
| Vault key | Android Keystore / iOS Keychain (via flutter_secure_storage) |
| Saved by the user | `Download/PDFNova/` (public, Android) |
| Output history, counters, theme | Hive boxes `recents` (≤200, schema v2) and `settings` |
| Quick note | Android SharedPreferences `notes_widget_prefs` (shared with the widget); Hive on iOS |

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
- **PDF → Word** can't reproduce exact layout *and* editability at once offline: pick Editable text or Exact look.
- **Word → PDF** keeps text, headings and line breaks only (no images, tables or styling). Shaped-script paragraphs are images with a hidden text layer: they look right and are searchable, but are slightly heavier than vector text, and extracted text may lose the space between a Latin label and the shaped words.
- **Syncfusion Community License** is free under US$1M revenue and ≤5 developers. Recheck before scaling.

### Fixed in this version (were open)
Word → PDF Unicode loss · PDF → Word duplicate content · PDF → PPT stretching · unencrypted vault · Notes app/widget split · Notes PDFs outside PDFNova · fake "PDF to Excel" folder · iOS Face ID string missing · placeholder tests · **pages getting the wrong size/rotation** in Merge (mixed sizes), Images → PDF (landscape photos) and Pages (rotations) — found by the new tests · header overflow with large system text · unhandled error log when a tool failed quickly · low-contrast secondary text (WCAG AA now met).

### Still open
- **iOS** is not verified on a device or simulator run (see Build & run). The Scan tool stays Android-only.
- **WiFi Share** has no access token or multi-file sessions yet ([docs/SECURITY.md](docs/SECURITY.md)).
- **Quick note** is not encrypted; vault screenshots are not blocked (`FLAG_SECURE`).
- No cancellation for long-running tools; progress is an estimated ramp, not measured.
- Compress / Fit to size / PDF → Images / PDF → PPT / OCR depend on platform plugins (PDFium, ML Kit) and are covered by device testing, not unit tests.
- **Unused Android resources**: `pdfnova_widget_info.xml`, `pdfnova_widget_layout.xml`, `pdfnova_widget_2x1.xml` are not registered in the manifest.
- README is out of date (tool count, PDF ↔ Word claims).

## 16. Build & run

```bash
flutter pub get
flutter test                # 80 tests: services, conversions, vault, history, widgets
flutter run                 # debug on a connected device
flutter build apk --release # Android release APK
flutter build appbundle     # Play Store bundle
```

**Working from an exFAT/FAT drive (e.g. PortableSSD):** macOS writes `._*` files there that break Gradle and the Flutter tool. Use the mirror script, which builds on the internal disk and copies APKs back to `build-local/`:

```bash
tool/local_build.sh test
tool/local_build.sh build apk --debug --target-platform android-arm64
tool/local_build.sh build apk --profile --target-platform android-arm64   # smaller, real animation speed
```

- **Release signing**: put credentials in `android/key.properties` (gitignored): `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Without it, release builds fall back to debug signing.
- **Android**: `MainActivity` extends `FlutterFragmentActivity` (required by `local_auth`). Java/Kotlin target 17. minSdk ≥ 23 (secure storage).
- **iOS**: Face ID purpose string, app icons from the PDF Nova mark, and a launch screen in the Folio canvas colour (light/dark) are configured. Scan is hidden automatically.
