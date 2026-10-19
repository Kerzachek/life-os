import 'package:flutter/material.dart';

import '../../../../core/sync/sync_state.dart';
import '../../../../core/theme/app_theme.dart';

/// Цветная плашка с текущим статусом синхронизации.
class SyncStatusBanner extends StatelessWidget {
  final SyncState state;

  const SyncStatusBanner({super.key, required this.state});

  Color get _color {
    if (state.activity == SyncActivity.error) return AppTheme.fireAccent;
    if (state.isBusy) return AppTheme.secondaryAccent;
    if (state.signedIn) return AppTheme.successAccent;
    return const Color(0xFF8B949E);
  }

  IconData get _icon {
    if (state.activity == SyncActivity.error) return Icons.cloud_off_rounded;
    if (state.signedIn) return Icons.cloud_done_rounded;
    return Icons.cloud_queue_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = _color;
    final showError = state.activity == SyncActivity.error &&
        state.errorMessage != null &&
        !state.offline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          state.isBusy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(_icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.label,
                  key: const ValueKey('sync_status_label'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (state.accountLabel != null)
                  Text(
                    state.accountLabel!,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                if (showError)
                  Text(
                    state.errorMessage!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
