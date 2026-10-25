import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../batch/batch_screen.dart';
import '../formfill/formfill_screen.dart';
import '../notes/notes_screen.dart';
import '../organize/organize_screen.dart';
import '../scan/scan_screen.dart';
import '../signature/signature_screen.dart';
import '../tool/tool_screen.dart';
import '../vault/vault_screen.dart';
import '../viewer/viewer_screen.dart';
import '../wifishare/wifishare_screen.dart';
import 'tools.dart';

/// The screen each tool opens into. Custom-flow tools have their own
/// screens; everything else uses the generic input → processing → success
/// journey in [ToolScreen].
Widget screenFor(Tool tool) => switch (tool.id) {
      ToolId.organize => OrganizeScreen(tool: tool),
      ToolId.sign => SignatureScreen(tool: tool),
      ToolId.formFill => FormFillScreen(tool: tool),
      ToolId.notes => NotesScreen(tool: tool),
      ToolId.scan => ScanScreen(tool: tool),
      ToolId.viewer => ViewerScreen(tool: tool),
      ToolId.vault => VaultScreen(tool: tool),
      ToolId.wifiShare => WifiShareScreen(tool: tool),
      ToolId.batch => BatchScreen(tool: tool),
      _ => ToolScreen(tool: tool),
    };

/// Opens a tool without a card to grow from (widget/shortcut launches).
/// Cards use a container transform instead — see ToolCard.
Future<void> openToolRoute(BuildContext context, Tool tool) =>
    Navigator.of(context).push(NovaRoute(page: screenFor(tool)));

