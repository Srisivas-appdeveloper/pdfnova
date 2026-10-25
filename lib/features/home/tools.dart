import 'package:flutter/material.dart';

enum ToolId {
  // Phase 1
  merge, split, compress, unlock, protect, imagesToPdf,
  // Phase 2
  organize, compressTarget, watermark, pdfToImages, metadata, pdfToText,
  // Phase 3
  scan, ocr,
  // Phase 4
  sign, formFill, pageNumbers, stamp, batch, viewer, vault, wifiShare,
  // Conversions
  pdfToWord, wordToPdf, pdfToPpt,
  // Notes
  notes,
}

class Tool {
  const Tool(this.id, this.title, this.subtitle, this.icon,
      {this.custom = false, this.androidOnly = false});
  final ToolId id;
  final String title;
  final String subtitle;
  final IconData icon;

  /// true → has its own screen instead of the generic input flow
  final bool custom;

  /// ML Kit scanner ships Android-only; tool is hidden on iOS
  final bool androidOnly;
}

class ToolSection {
  const ToolSection(this.title, this.tools);
  final String title;
  final List<Tool> tools;
}

const toolSections = <ToolSection>[
  ToolSection('Organize', [
    Tool(ToolId.merge, 'Merge', 'Combine PDFs into one', Icons.merge_rounded),
    Tool(ToolId.split, 'Split', 'Extract a page range',
        Icons.content_cut_rounded),
    Tool(ToolId.organize, 'Pages', 'Reorder · rotate · delete',
        Icons.grid_view_rounded, custom: true),
    Tool(ToolId.batch, 'Batch', 'One action, many PDFs',
        Icons.dynamic_feed_rounded, custom: true),
  ]),
  ToolSection('Shrink & convert', [
    Tool(ToolId.compress, 'Compress', 'Quick size reduction',
        Icons.compress_rounded),
    Tool(ToolId.compressTarget, 'Fit to size', 'Under 200KB / 500KB / 1MB',
        Icons.straighten_rounded),
    Tool(ToolId.imagesToPdf, 'Images → PDF', 'Photos into one PDF',
        Icons.photo_library_rounded),
    Tool(ToolId.pdfToImages, 'PDF → Images', 'Every page as a picture',
        Icons.collections_rounded),
    Tool(ToolId.pdfToText, 'PDF → Text', 'Pull out all the text',
        Icons.notes_rounded),
    Tool(ToolId.pdfToWord, 'PDF → Word', 'Export as editable .docx',
        Icons.description_rounded),
    Tool(ToolId.wordToPdf, 'Word → PDF', 'Convert .docx to PDF',
        Icons.picture_as_pdf_rounded),
    Tool(ToolId.pdfToPpt, 'PDF → PPT', 'Each page as a slide',
        Icons.slideshow_rounded),
  ]),
  ToolSection('Secure', [
    Tool(ToolId.unlock, 'Unlock', 'Aadhaar & password PDFs',
        Icons.lock_open_rounded),
    Tool(ToolId.protect, 'Protect', 'Add AES-256 password',
        Icons.shield_rounded),
    Tool(ToolId.watermark, 'Watermark', 'Your text across pages',
        Icons.branding_watermark_rounded),
    Tool(ToolId.metadata, 'Clean metadata', 'Strip author & history',
        Icons.cleaning_services_rounded),
    Tool(ToolId.vault, 'Vault', 'Fingerprint-locked files',
        Icons.fingerprint_rounded, custom: true),
  ]),
  ToolSection('Smart', [
    Tool(ToolId.scan, 'Scan', 'Camera → clean PDF', Icons.document_scanner_rounded,
        custom: true, androidOnly: true),
    Tool(ToolId.ocr, 'OCR', 'Read text from scans', Icons.translate_rounded),
    Tool(ToolId.sign, 'Sign', 'Draw & place a signature',
        Icons.draw_rounded, custom: true),
    Tool(ToolId.formFill, 'Fill form', 'Type into PDF forms',
        Icons.edit_note_rounded, custom: true),
    Tool(ToolId.notes, 'Quick Notes', 'Write & save PDF notes',
        Icons.note_alt_rounded, custom: true),
  ]),
  ToolSection('More', [
    Tool(ToolId.pageNumbers, 'Page numbers', 'Stamp 1, 2, 3…',
        Icons.format_list_numbered_rounded),
    Tool(ToolId.stamp, 'Stamp', 'PAID · APPROVED · custom',
        Icons.approval_rounded),
    Tool(ToolId.viewer, 'Reader', 'Night mode + read aloud',
        Icons.menu_book_rounded, custom: true),
    Tool(ToolId.wifiShare, 'WiFi share', 'Phone → phone, no internet',
        Icons.wifi_tethering_rounded, custom: true),
  ]),
];

/// Flat list (used by batch mode + lookups)
final allTools = [for (final s in toolSections) ...s.tools];

/// Index of the section a tool belongs to — drives its tint colour.
int sectionIndexOf(Tool tool) =>
    toolSections.indexWhere((s) => s.tools.any((t) => t.id == tool.id));
