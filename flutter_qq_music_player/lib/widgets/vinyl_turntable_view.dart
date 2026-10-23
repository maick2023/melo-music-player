import 'package:flutter/material.dart';
import '../models/song_model.dart';

/// 样式一：仿 QQ 音乐经典黑胶唱针旋转视图
class VinylTurntableView extends StatefulWidget {
  final SongModel song;
  final bool isPlaying;

  const VinylTurntableView({
    super.key,
    required this.song,
    required this.isPlaying,
  });

  @override
  State<VinylTurntableView> createState() => _VinylTurntableViewState();
}

class _VinylTurntableViewState extends State<VinylTurntableView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    if (widget.isPlaying) _spinController.repeat();
  }

  @override
  void didUpdateWidget(covariant VinylTurntableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_spinController.isAnimating) {
      _spinController.repeat();
    } else if (!widget.isPlaying && _spinController.isAnimating) {
      _spinController.stop();
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 呼吸感外层光晕
        Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.song.dominantColor.withOpacity(0.28),
                blurRadius: 56,
                spreadRadius: 12,
              ),
            ],
          ),
        ),
        // 黑胶唱片盘面
        RotationTransition(
          turns: _spinController,
          child: Container(
            width: 280,
            height: 280,
            padding: const EdgeInsets.all(44),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Color(0xFF27272A),
                  Color(0xFF09090B),
                  Color(0xFF18181B),
                  Color(0xFF09090B),
                ],
                stops: [0.2, 0.55, 0.82, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 6,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [widget.song.dominantColor, widget.song.accentColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.black87, width: 4),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.song.format.split(' ').first,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 顶部仿真机械唱针（随播放/暂停平滑旋转起落）
        Positioned(
          top: 4,
          right: 68,
          child: AnimatedRotation(
            turns: widget.isPlaying ? 0.0 : -0.08,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            alignment: Alignment.topCenter,
            child: Container(
              width: 18,
              height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFFE2E8F0), Color(0xFF64748B)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 12,
                    offset: Offset(2, 6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
