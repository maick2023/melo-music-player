import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 车载蓝牙 (A2DP) / CarPlay / Android Auto 连接检测与车子点火自动播放服务
class CarAutoPlayService {
  StreamSubscription<AudioDevicesChangedEvent>? _deviceSub;
  bool autoPlayOnCarConnect = true;
  bool launchCarModeUi = true;
  bool rememberLastPosition = true;
  List<String> trustedCarBluetoothKeywords = [
    'CAR',
    'AUTO',
    'BMW',
    'BENZ',
    'AUDI',
    'TESLA',
    'BYD',
    'XIAOMI',
    'CARPLAY',
    'MY CAR',
    '车载',
  ];

  final void Function(String deviceName) onCarConnectedTriggerPlay;
  final void Function() onCarDisconnectedTriggerPause;

  CarAutoPlayService({
    required this.onCarConnectedTriggerPlay,
    required this.onCarDisconnectedTriggerPause,
  });

  /// 初始化监听系统音频输出设备变化（当汽车启动、车载蓝牙或 CarPlay 握手成功时立即触发）
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    autoPlayOnCarConnect = prefs.getBool('car_auto_play') ?? true;
    launchCarModeUi = prefs.getBool('car_mode_ui') ?? true;
    rememberLastPosition = prefs.getBool('car_remember_pos') ?? true;

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _deviceSub = session.devicesChangedEventStream.listen((event) {
      if (!autoPlayOnCarConnect) return;

      // 1. 检测新连接的音频输出设备是否包含车载蓝牙 (Bluetooth A2DP) 或 CarPlay / USB Audio
      for (final device in event.devicesAdded) {
        final nameUpper = device.name.toUpperCase();
        final isBluetoothOrCar = device.type == AudioDeviceType.bluetoothA2dp ||
            device.type == AudioDeviceType.carAudio ||
            trustedCarBluetoothKeywords.any((k) => nameUpper.contains(k));

        if (isBluetoothOrCar) {
          onCarConnectedTriggerPlay(device.name);
          break;
        }
      }

      // 2. 当车辆熄火断开车载蓝牙时，自动暂停并保存当前播放毫秒进度
      for (final device in event.devicesRemoved) {
        if (device.type == AudioDeviceType.bluetoothA2dp ||
            device.type == AudioDeviceType.carAudio) {
          onCarDisconnectedTriggerPause();
          break;
        }
      }
    });
  }

  Future<void> updateSettings({
    bool? autoPlay,
    bool? carUi,
    bool? rememberPos,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (autoPlay != null) {
      autoPlayOnCarConnect = autoPlay;
      await prefs.setBool('car_auto_play', autoPlay);
    }
    if (carUi != null) {
      launchCarModeUi = carUi;
      await prefs.setBool('car_mode_ui', carUi);
    }
    if (rememberPos != null) {
      rememberLastPosition = rememberPos;
      await prefs.setBool('car_remember_pos', rememberPos);
    }
  }

  void dispose() {
    _deviceSub?.cancel();
  }
}
