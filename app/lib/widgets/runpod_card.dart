import 'package:flutter/material.dart';

import '../runpod.dart';
import 'common.dart';

String fmtUsd(double? v) => v == null ? '–' : '\$${v.toStringAsFixed(2)}';

/// Üst çubukta sürekli görünen bakiye rozeti (her ekranda).
class BalanceChip extends StatelessWidget {
  const BalanceChip({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: RunPod.I,
      builder: (context, _) {
        final rp = RunPod.I;
        if (!rp.configured) return const SizedBox.shrink();
        final live = rp.pod != null;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (live ? Colors.orange : Colors.green).withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet_outlined, size: 16, color: live ? Colors.orangeAccent : Colors.greenAccent),
                const SizedBox(width: 6),
                Text(fmtUsd(rp.balance), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (live) ...[
                  const SizedBox(width: 6),
                  Text('−${fmtUsd(rp.pod!.costPerHr)}/sa', style: const TextStyle(fontSize: 11, color: Colors.orangeAccent)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Ana ekrandaki RunPod kartı: bakiye, pod durumu, Aç/Kapat.
class RunPodCard extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const RunPodCard({super.key, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: RunPod.I,
      builder: (context, _) {
        final rp = RunPod.I;
        if (!rp.configured) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off, color: Colors.amber),
              title: const Text('RunPod bağlı değil'),
              subtitle: const Text('Ayarlar → RunPod API anahtarını gir; sunucuyu buradan aç/kapat.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenSettings,
            ),
          );
        }
        final pod = rp.pod;
        final opt = RunPod.gpuOptions[rp.gpu]!;
        String statusText;
        Color statusColor;
        if (pod == null) {
          statusText = rp.working ? (rp.stage.isEmpty ? 'Açılıyor…' : rp.stage) : 'Sunucu kapalı · ücret işlemiyor';
          statusColor = rp.working ? Colors.amber : cs.onSurface.withOpacity(0.7);
        } else if (rp.ready) {
          statusText = 'HAZIR · ${pod.gpuName} · ${fmtSeconds(pod.uptimeSeconds)} · bu açılış ≈ ${fmtUsd(pod.spent)}';
          statusColor = Colors.greenAccent;
        } else {
          statusText = '${rp.stage.isEmpty ? 'Başlıyor…' : rp.stage} · ${pod.gpuName}';
          statusColor = Colors.amber;
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: cs.onSurface.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: (pod != null ? Colors.orange : Colors.green).withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.memory, size: 20),
                  const SizedBox(width: 8),
                  const Text('RunPod sunucu', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  Text('Bakiye ', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                  Text(fmtUsd(rp.balance), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (rp.working)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  Expanded(child: Text(statusText, style: TextStyle(fontSize: 13, color: statusColor), maxLines: 3)),
                ],
              ),
              if (rp.volumeNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(rp.volumeNote!, style: const TextStyle(fontSize: 12, color: Colors.amber), maxLines: 4),
                ),
              if (rp.lastError != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Expanded(child: SelectableText(rp.lastError!, style: const TextStyle(fontSize: 12, color: Colors.redAccent))),
                      IconButton(icon: const Icon(Icons.close, size: 18), onPressed: rp.clearError),
                    ],
                  ),
                ),
              if (rp.apiError != null && rp.lastError == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('RunPod sorgusu: ${rp.apiError}', style: const TextStyle(fontSize: 12, color: Colors.redAccent), maxLines: 3),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: pod == null
                        ? FilledButton.icon(
                            onPressed: rp.working ? null : () => rp.open(),
                            icon: const Icon(Icons.power_settings_new),
                            label: Text(rp.working ? 'Açılıyor…' : 'Sunucuyu Aç  (${opt.label.split(' ').first}, ${fmtUsd(opt.pricePerHr)}/sa)'),
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: rp.working && rp.stage.startsWith('Kapat') ? null : () => _confirmClose(context),
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('Sunucuyu Kapat'),
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                  ),
                  if (rp.working && pod == null) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(onPressed: rp.cancelOpen, icon: const Icon(Icons.close), tooltip: 'İptal'),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                pod == null
                    ? (rp.useReadyImage ? 'Hazır imaj: açılış ~2 dk.' : rp.useVolume ? 'Kalıcı disk: açılış ~1-2 dk (ilk seferde ~10 dk).' : 'Her açılışta kurulum: ~10 dk.') + ' ${rp.idleMinutes} dk iş gelmezse kendini kapatır.'
                    : 'İşin bitince kapat; ${rp.idleMinutes} dk boşta kalırsa kendisi kapanır.',
                style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.55)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmClose(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sunucu kapatılsın mı?'),
        content: Text(RunPod.I.useVolume ? 'Kurulum kalıcı diskte kalır, sonraki açılış hızlı olur.' : 'Kurulum silinir; sonraki açılış ~10 dk sürer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kapat')),
        ],
      ),
    );
    if (ok == true) await RunPod.I.close();
  }
}
