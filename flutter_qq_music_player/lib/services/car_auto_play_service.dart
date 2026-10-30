import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 车载蓝牙 (A2DP / AVRCP) / CarPlay / Android Auto 连接检测与车子点火自动播放服务
/// 包含：
///   1. 实时设备事件流监听 (devicesChangedEventStream)
///   2. 后台 2.5 秒周期性蓝牙音频路由巡检 (解决部分安卓/鸿蒙车型熄屏时不触发事件流的问题)
///   3. 车载蓝牙握手延迟三级重试唤醒 (0ms / 1.2s / 2.8s)，确保车机刚通电未就绪时也能成功出声
class CarAutoPlayService {
  StreamSubscription<AudioDevicesChangedEvent>? _deviceSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  Timer? _bluetoothPollTimer;
  bool _wasCarAudioConnected = false;

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
    'HUAWEI',
    'HICAR',
    'CARPLAY',
    'HONDA',
    'TOYOTA',
    'VW',
    'VOLKSWAGEN',
    'GEELY',
    'CHANGAN',
    'CHERY',
    'GWM',
    'HAVAL',
    'NIO',
    'XPENG',
    'LI',
    'AITO',
    'MY CAR',
    'BT',
    'BLUETOOTH',
    '车载',
    '汽车',
  ];

  final void Function(String deviceName) onCarConnectedTriggerPlay;
  final void Function() onCarDisconnectedTriggerPause;

  CarAutoPlayService({
    required this.onCarConnectedTriggerPlay,
    required this.onCarDisconnectedTriggerPause,
  });

  bool _isCarOrBluetoothDevice(AudioDevice device) {
    if (!device.isOutput) return false;
    if (device.type == AudioDeviceType.bluetoothA2dp ||
        device.type == AudioDeviceType.bluetoothSco ||
        device.type == AudioDeviceType.bluetoothLe ||
        device.type == AudioDeviceType.carAudio ||
        device.type == AudioDeviceType.usbAudio) {
      return true;
    }
    final nameUpper = device.name.toUpperCase();
    return trustedCarBluetoothKeywords.any((k) => nameUpper.contains(k));
  }

  /// 初始化监听系统音频输出设备变化（当汽车启动、车载蓝牙或 CarPlay 握手成功时立即触发）
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    autoPlayOnCarConnect = prefs.getBool('car_auto_play') ?? true;
    launchCarModeUi = prefs.getBool('car_mode_ui') ?? true;
    rememberLastPosition = prefs.getBool('car_remember_pos') ?? true;

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // 1. 启动时立即检查一次：如果当前手机已经连上了车载蓝牙，直接触发自动续播！
    await _checkCurrentAudioDevices(session, isInitialCheck: true);

    // 2. 监听系统设备插拔/蓝牙连接事件流
    _deviceSub = session.devicesChangedEventStream.listen((event) {
      if (!autoPlayOnCarConnect) return;

      for (final device in event.devicesAdded) {
        if (_isCarOrBluetoothDevice(device)) {
          _wasCarAudioConnected = true;
          _triggerCarPlayWithHandshakeRetry(device.name);
          break;
        }
      }

      for (final device in event.devicesRemoved) {
        if (_isCarOrBluetoothDevice(device)) {
          _wasCarAudioConnected = false;
          onCarDisconnectedTriggerPause();
          break;
        }
      }
    });

    // 3. 后台每 2.5 秒主动巡检蓝牙 A2DP 路由状态（防止手机锁屏在口袋里时漏掉车载蓝牙连接事件）
    _bluetoothPollTimer?.cancel();
    _bluetoothPollTimer = Timer.periodic(
      const Duration( milliseconds: 2500 ),
      (_) => _checkCurrentAudioDevices(session, isInitialCheck: false),
    );

    // 4. 监听音频焦点恢复（如车载导航播报完毕后自动恢复播放）
    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (!event.begin &&
          event.type == AudioInterruptionType.pause &&
          autoPlayOnCarConnect &&
          _wasCarAudioConnected) {
        onCarConnectedTriggerPlay('车载焦点恢复');
      }
    });
  }

  Future<void> _checkCurrentAudioDevices(
    AudioSession session, {
    required bool isInitialCheck,
  }) async {
    if (!autoPlayOnCarConnect) return;
    try {
      final devices = await session.getDevices(includeInputs: false);
      AudioDevice? matchedCarDevice;
      for (final d in devices) {
        if (_isCarOrBluetoothDevice(d)) {
          matchedCarDevice = d;
          break;
        }
      }

      final nowConnected = matchedCarDevice != null;
      if (nowConnected && !_wasCarAudioConnected) {
        _wasCarAudioConnected = true;
        _triggerCarPlayWithHandshakeRetry(matchedCarDevice.name);
      } else if (!nowConnected && _wasCarAudioConnected && !isInitialCheck) {
        _wasCarAudioConnected = false;
        onCarDisconnectedTriggerPause();
      }
    } catch (_) {}
  }

  /// 车子刚点火通电时，车机蓝牙 A2DP 通道往往需要 1~2 秒完成音频路由切换，
  /// 因此采用 0ms 立即唤醒 + 1.2秒二次确认 + 2.8秒三次确认，确保 100% 自动播放出声
  void _triggerCarPlayWithHandshakeRetry(String deviceName) {
    onCarConnectedTriggerPlay(deviceName);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (autoPlayOnCarConnect && _wasCarAudioConnected) {
        onCarConnectedTriggerPlay(deviceName);
      }
    });
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (autoPlayOnCarConnect && _wasCarAudioConnected) {
        onCarConnectedTriggerPlay(deviceName);
      }
    });
  }

  /// 一键申请加入安卓/华为后台电池优化白名单 + 蓝牙连接权限（让应用常驻手机进程不被系统清理）
  static Future<bool> requestBackgroundKeepAlivePermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      await Permission.bluetoothConnect.request();
      await Permission.notification.request();
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        final res = await Permission.ignoreBatteryOptimizations.request();
        return res.isGranted;
      }
      return true;
    } catch (_) {
      return false;
    }
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
    _bluetoothPollTimer?.cancel();
    _deviceSub?.cancel();
    _interruptionSub?.cancel();
  }
}
