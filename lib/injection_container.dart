// file: lib/injection_container.dart

import 'package:get_it/get_it.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_event.dart';

import 'core/config/detection_config.dart';
import 'core/services/camera_service.dart';
import 'features/detection/data/datasources/detection_local_datasource.dart';
import 'features/detection/data/datasources/detection_local_datasource_impl.dart';
import 'features/detection/data/repositories/detection_repository_impl.dart';
import 'features/detection/domain/repositories/detection_repository.dart';
import 'features/detection/domain/usecases/load_model_usecase.dart';
import 'features/detection/domain/usecases/detection_object_from_frame.dart';
import 'features/detection/presentation/bloc/detection_bloc.dart';
import 'features/tts/data/datasources/tts_service.dart';
import 'features/tts/data/repositories/tts_repository_impl.dart';
import 'features/tts/domain/repositories/tts_repository.dart';
import 'features/tts/domain/usecases/speak_warning_usecase.dart';
import 'features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'features/tts/domain/usecases/pause_speaking_usecase.dart';
import 'features/tts/domain/usecases/configure_tts_usecase.dart';
import 'features/tts/presentation/bloc/tts_bloc.dart';
import 'features/settings/data/datasources/local_storage_service.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/settings/presentation/bloc/settings_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  sl.registerSingleton<LocalStorageService>(LocalStorageService());
  sl.registerSingleton<SettingsRepository>(
    SettingsRepositoryImpl(sl<LocalStorageService>()),
  );
  // ── TTS ─────────────────────────────────────────────────────────────────
  final ttsService = TtsService();
  await ttsService.initialize(); // Khởi tạo với all defaults
  sl.registerSingleton<TtsService>(ttsService);

  sl.registerSingleton<TtsRepository>(TtsRepositoryImpl(sl<TtsService>()));
  sl.registerSingleton(SpeakWarningUsecase(sl<TtsRepository>()));
  sl.registerSingleton(StopSpeakingUsecase(sl<TtsRepository>()));
  sl.registerSingleton(PauseSpeakingUsecase(sl<TtsRepository>())); // Bug 9 FIX
  sl.registerSingleton(ConfigureTtsUsecase(sl<TtsRepository>()));  // Bug 11 FIX

  sl.registerSingleton(TtsBloc(
    speakWarning:  sl(),
    stopSpeaking:  sl(),
    pauseSpeaking: sl<PauseSpeakingUsecase>(), // Bug 9 FIX
    settingsRepository: sl<SettingsRepository>(),
  ));

  // ── Detection Config (core — shared giữa Detection và Settings) ──────────
  // Bug 4 FIX: Singleton DetectionConfig — cả datasource và settings đều ref cùng instance
  sl.registerSingleton(DetectionConfig());

  // ── Detection ────────────────────────────────────────────────────────────
  sl.registerSingleton<DetectionLocalDatasource>(
    // Bug 4 FIX: Inject DetectionConfig vào datasource
    DetectionLocalDatasourceImpl(sl<DetectionConfig>()),
  );
  sl.registerSingleton<DetectionRepository>(DetectionRepositoryImpl(sl()));
  sl.registerSingleton(LoadModelUsecase(sl<DetectionRepository>()));
  sl.registerSingleton(DetectionObjectFromFrame(sl<DetectionRepository>()));

  // Bug 10 FIX: DetectionBloc không còn nhận TtsBloc
  // Thay bằng callback — page là orchestrator, không phải bloc
  sl.registerFactory(() => DetectionBloc(
    loadModel:       sl(),
    detectFromFrame: sl(),
    onWarning: ({
      required String text,
      required bool immediate,
      required bool withVibration,
    }) {
      // TtsBloc singleton luôn available khi factory được gọi
      sl<TtsBloc>().add(
        TtsSpeak(text, immediate: immediate, withVibration: withVibration),
      );
    },
  ));

  // ── Camera ───────────────────────────────────────────────────────────────
  sl.registerSingleton(CameraService());

  // ── Settings ─────────────────────────────────────────────────────────────

  // Bug 11 FIX: SettingsBloc nhận ConfigureTtsUsecase thay vì TtsService
  // Bug 4 FIX:  SettingsBloc nhận DetectionConfig để update live threshold
  sl.registerFactory(() => SettingsBloc(
    sl<SettingsRepository>(),
    sl<ConfigureTtsUsecase>(),
    sl<StopSpeakingUsecase>(),
    sl<DetectionConfig>(),
  ));
}
