import 'package:flutter/material.dart';
import '../../features/viewer/ppt_viewer_screen.dart';
import '../../services/file_service.dart';

/// Opens any output file the best in-app way: .pptx gets the built-in slide
/// viewer (works with no PowerPoint installed); everything else goes to the
/// system handler via open_filex.
void openAnyFile(BuildContext context, String path) {
  if (path.toLowerCase().endsWith('.pptx')) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PptViewerScreen(path: path)),
    );
  } else {
    FileService.instance.open(path);
  }
}
