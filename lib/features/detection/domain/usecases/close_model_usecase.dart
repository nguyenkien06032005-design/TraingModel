import '../repositories/detection_repository.dart';
import '../../../../core/usecases/usecase.dart';

/// FIX SV-007: Tách CloseModelUsecase để DetectionBloc không phụ thuộc
/// trực tiếp vào DetectionRepository — đúng nguyên tắc Clean Architecture.
///
/// Trước đây DetectionBloc inject cả DetectionRepository chỉ để gọi closeModel().
/// Điều này vi phạm: Presentation layer không nên biết về Data layer contracts.
class CloseModelUsecase implements UseCase<void, NoParams> {
  final DetectionRepository _repository;
  CloseModelUsecase(this._repository);

  @override
  Future<void> call(NoParams params) => _repository.closeModel();

  /// Convenience method — gọi mà không cần truyền NoParams()
  Future<void> close() => _repository.closeModel();
}
