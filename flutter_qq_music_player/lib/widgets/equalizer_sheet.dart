import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/eq_preset_model.dart';
import '../services/audio_player_service.dart';

/// 仿 QQ 音乐银河音效与 5 段均衡器调节底部弹窗
class EqualizerSheet extends ConsumerWidget {
  const EqualizerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioPlayerProvider);
    final controller = ref.read(audioPlayerProvider.notifier);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF121A24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '银河音效 · 均衡器调节',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: state.surround3dEnabled,
                activeColor: const Color(0xFF00D676),
                onChanged: controller.toggleSurround3d,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: EqPresetModel.builtinPresets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final preset = EqPresetModel.builtinPresets[idx];
                final selected = preset.id == state.activeEqPreset.id;
                return ChoiceChip(
                  label: Text(preset.name),
                  selected: selected,
                  selectedColor: const Color(0xFF00D676),
                  onSelected: (_) => controller.applyEqPreset(preset),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(EqPresetModel.bandLabels.length, (i) {
            return Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    EqPresetModel.bandLabels[i],
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: state.customEqGains[i],
                    min: -12.0,
                    max: 12.0,
                    activeColor: const Color(0xFF00D676),
                    onChanged: (v) => controller.updateEqBand(i, v),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${state.customEqGains[i].toStringAsFixed(1)}dB',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
