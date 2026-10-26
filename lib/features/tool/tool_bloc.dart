import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/storage_service.dart';
import '../../services/tool_errors.dart';
import '../../services/tool_notes.dart';

export '../../services/tool_notes.dart';
import '../home/tools.dart';

// ---- Events ------------------------------------------------------------
sealed class ToolEvent extends Equatable {
  const ToolEvent();
  @override
  List<Object?> get props => [];
}

/// Runs [task] (the actual work, returning one or more output file paths).
/// Progress is only what the task actually reports via [ToolProgress];
/// otherwise the UI shows an indeterminate indicator — never an invented
/// percentage.
class ToolStarted extends ToolEvent {
  const ToolStarted(this.tool, this.task);
  final Tool tool;
  final Future<List<String>> Function() task;
  @override
  List<Object?> get props => [tool.id];
}

// ---- States ------------------------------------------------------------
sealed class ToolState extends Equatable {
  const ToolState();
  @override
  List<Object?> get props => [];
}

class ToolIdle extends ToolState {
  const ToolIdle();
}

class ToolProcessing extends ToolState {
  const ToolProcessing(this.progress, {this.stage});

  /// 0–1 when the task measures it; null while the amount is unknown.
  final double? progress;

  /// Optional stage label, e.g. "File 2 of 5".
  final String? stage;
  @override
  List<Object?> get props => [progress, stage];
}

class ToolSuccess extends ToolState {
  const ToolSuccess(this.paths, {this.notes = const []});
  final List<String> paths;

  /// Honest caveats about the result (e.g. text that could not be
  /// embedded), shown under the result. Empty for a clean result.
  final List<String> notes;
  @override
  List<Object?> get props => [paths, notes];
}

class ToolFailure extends ToolState {
  const ToolFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// ---- Bloc --------------------------------------------------------------
class ToolBloc extends Bloc<ToolEvent, ToolState> {
  ToolBloc() : super(const ToolIdle()) {
    on<ToolStarted>(_run);
  }

  Future<void> _run(ToolStarted e, Emitter<ToolState> emit) async {
    emit(const ToolProcessing(null));
    try {
      final notes = <String>[];
      final paths = await ToolNotes.collect(
        notes,
        () => ToolProgress.track((fraction, stage) {
          if (!isClosed) emit(ToolProcessing(fraction, stage: stage));
        }, e.task),
      );
      if (isClosed) return;
      if (paths.isEmpty) {
        // Cancelled (e.g. the scanner was closed) — back to the input.
        emit(const ToolIdle());
        return;
      }
      await StorageService.instance.addOutputs(paths, e.tool.title);
      await StorageService.instance.incrementOps();
      emit(ToolSuccess(paths, notes: notes));
    } catch (err) {
      if (isClosed) return;
      emit(ToolFailure(
          describeToolError(err, isUnlockTool: e.tool.id == ToolId.unlock)));
    }
  }
}
