import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/storage_service.dart';
import '../../services/tool_notes.dart';

export '../../services/tool_notes.dart';
import '../home/tools.dart';

// ---- Events ------------------------------------------------------------
sealed class ToolEvent extends Equatable {
  const ToolEvent();
  @override
  List<Object?> get props => [];
}

/// Runs [task] (the actual work, returning one or more output file paths)
/// with a smooth progress ramp: 0→90% eased while the real work runs, snap
/// to 100% on completion. The wait shown is always the real wait.
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
  const ToolProcessing(this.progress);
  final double progress;
  @override
  List<Object?> get props => [progress];
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
    emit(const ToolProcessing(0));
    try {
      var done = false;
      final notes = <String>[];
      final work =
          ToolNotes.collect(notes, e.task).whenComplete(() => done = true);
      // The task may fail while the ramp below is still waiting; without a
      // listener that error would be reported as unhandled before the
      // `await work` further down catches it. ignore() only marks it as
      // observed — awaiting still rethrows.
      work.ignore();

      var p = 0.0;
      while (!done && p < 0.9) {
        await Future.delayed(const Duration(milliseconds: 90));
        p += (0.9 - p) * 0.06;
        if (!done && !isClosed) emit(ToolProcessing(p));
      }
      final paths = await work;
      if (isClosed) return;
      emit(const ToolProcessing(1));
      await Future.delayed(const Duration(milliseconds: 350));
      if (isClosed) return;
      if (paths.isEmpty) {
        emit(const ToolIdle());
        return;
      }
      await StorageService.instance.addOutputs(paths, e.tool.title);
      await StorageService.instance.incrementOps();
      emit(ToolSuccess(paths, notes: notes));
    } catch (err) {
      if (isClosed) return;
      final text = err.toString();
      final msg = text.contains('password')
          ? 'That password did not open this PDF. Check the name spelling and year, then try again.'
          : text.contains('NoText')
              ? 'No readable text was found in this PDF.'
              : 'Something went wrong while processing. The file may be corrupted — try another copy.';
      emit(ToolFailure(msg));
    }
  }
}
