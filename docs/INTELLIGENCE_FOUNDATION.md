# Nova Intelligence — Foundation Plan

Status: **local content index + search shipped (Milestone G)**. No AI
model, embedding store or backend has been added; Ask Nova (Milestone H)
is not implemented — see §5. This document records what exists, what
can be reused, and the smallest next steps, so a future assistant ("Ask
Nova") can be built without disturbing the current offline tools.

## 1. What already exists (reuse, don't rebuild)

| Need | Existing piece | Notes |
|---|---|---|
| Page-associated text | [`DocumentTextService`](../lib/services/document_text_service.dart) → `List<PageText>` | **New in this release.** Text layer first, ML Kit OCR only for pages without text, every page tagged with `page` number and `source` (`textLayer` / `ocr` / `none`). Already used by PDF → Text and PDF → Word. Uses line extraction because Syncfusion's plain `extractText()` mis-decodes text after a font switch. |
| OCR | [`OcrService`](../lib/services/ocr_service.dart) (ML Kit Latin + Devanagari) | On-device. Injected into `DocumentTextService` so tests can fake it. |
| Rendering | [`RasterService`](../lib/services/raster_service.dart) (PDFium via pdfx) | Thumbnails / page images for citations ("show me page 4"). |
| Document surgery | [`PdfService`](../lib/services/pdf_service.dart), [`ConversionService`](../lib/services/conversion_service.dart) | The future Action Engine's operation registry should wrap these, not duplicate them. |
| Job runner + progress | [`ToolBloc`](../lib/features/tool/tool_bloc.dart) | Runs any `Future<List<String>> Function()`; reports progress, maps errors, records outputs. `ToolNotes` lets a job attach honest caveats to its result. |
| Output history | `StorageService.history` (`OutputRecord`) | Single source of truth for generated files. |
| Heavy work off the UI isolate | `PdfService._offUi` (`Isolate.run` + `BackgroundIsolateBinaryMessenger`) | Pattern for indexing large documents. |

## 2. Gaps, and the smallest useful fix for each

1. **Document identity.** There is no stable ID for a *source* document (only output paths).
   *Next:* `DocumentRef { id = SHA-256 of bytes, name, pageCount, size, addedAt }` — content hash makes re-indexing idempotent and survives renames.
2. **Derived-data store.** Page texts are recomputed each time.
   *Next:* a per-document cache `<app support>/derived/<docId>/pages.json` (`PageText` list + extractor version). Plain files are enough until search needs ranking; then evaluate `sqlite3` FTS5 (on-device, small, no server). Deleting a document's history entry should offer to delete its derived folder.
3. **Search.** Keyword search over cached `PageText` gives page-level hits immediately; no model needed.
4. **Cancellation.** `ToolBloc` cannot cancel. *Next:* a `CancelToken` checked between pages in `DocumentTextService.extract` and OCR loops (isolate work cannot be interrupted mid-page; say so in the UI).
5. **Model runtime.** Not chosen. Requirements to evaluate before adding any dependency: model size on disk (< 1.5 GB), peak RAM on a 4 GB Android phone, cold-load time, tokens/s, Tamil/Hindi quality, licence, offline install from a user-confirmed download. Candidates to benchmark: llama.cpp-based runtimes with a small instruct model, and MediaPipe LLM Inference. Core PDF tools must keep working with no model installed.

## 3. Proposed interfaces (not yet implemented)

```dart
abstract class DocumentIndex {
  Future<void> index(DocumentRef doc, List<PageText> pages);
  Future<List<SearchHit>> search(String query, {Set<String>? docIds});
  Future<void> remove(String docId); // removes derived data only
}

class SearchHit { final String docId; final int page; final String snippet; }

abstract class LocalModel {          // future, behind a capability check
  Future<bool> get isInstalled;
  Stream<String> answer(String question, List<SearchHit> evidence);
}
```

Answers must cite `SearchHit.page`; if retrieval finds nothing, the assistant says so instead of answering.

## 4. Shipped: local content index (Milestone G)

[`DocumentIndex`](../lib/services/document_index.dart) — opt-in ("Search inside files" in Settings, off by default).

| Aspect | Behaviour (all covered by tests) |
|---|---|
| Scope | Only PDFs in output history (files PDF Nova created). The vault is never indexed. |
| Storage | `<app support>/content_index/<sha256(path)>.json`: path, SHA-256 fingerprint, indexed time, `[{page, text}]`. Written atomically. |
| Extraction | Text layer via line extraction on a background isolate. No OCR: scanned pages are counted as unsearchable, not hidden. Locked/damaged PDFs are skipped. |
| Change detection | Fingerprint compare; unchanged files are not re-extracted, changed files are re-indexed. |
| Consistency | Hooked into history: add → index; rename → move; remove from history / prune missing → drop. `sync()` reconciles; "Rebuild index" starts fresh. |
| Privacy | Turning the setting off deletes the whole index. Nothing leaves the device. |
| Search | Case-insensitive phrase search → `SearchHit {path, page, snippet, match offsets}`; Files shows "Inside files" separately from file-name matches; a hit opens the Reader at that page (verified on device). |

Not yet: ranking beyond page order, OCR'd text in the index, cancellation of a long sync, SQLite/FTS (plain JSON is enough at ≤200 documents).

## 5. Ask Nova — not implemented (blocked on a decision)

Grounded Q&A needs a language model. Before adding one, these must be decided by the product owner (they change app size, cost and privacy promises):

1. **On-device vs remote.** On-device keeps the "nothing leaves your phone" promise but adds roughly 0.5–2 GB of model download and needs a recent phone. Remote is small but must be opt-in per question, disclosed, and never described as on-device.
2. **Model + runtime**, after benchmarking on a mid-range Android phone: size, peak RAM, load time, tokens/s, Tamil/Hindi quality, licence.
3. **Distribution:** explicit, user-confirmed model download (Play size limits rule out bundling).

What already exists for it: page-associated text (`DocumentTextService`), retrieval with page references (`DocumentIndex.search`), open-at-page in the Reader. A first Ask Nova should answer only from retrieved passages, cite pages, and say "not found in this document" otherwise.

Milestone I (controlled actions) depends on H and is also not started.

## 6. Explicitly out of scope for now
No "Ask Nova" entry point, no model download, no embeddings, no cloud calls until §5 is decided.
