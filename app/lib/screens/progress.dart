import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/runpod_card.dart';
import 'result.dart';

/// İş ilerlemesi: yüzde, aşama, kalan süre, iptal.
class ProgressScreen extends StatefulWidget {
  final String jobId;
  const ProgressScreen({super.key, required this.jobId});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  Job? _job;
  String? _error;
  int _failCount = 0;
  Timer? _timer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final j = await Api.I.job(widget.jobId);
      if (!mounted) return;
      setState(() {
        _job = j;
        _error = null;
        _failCount = 0;
      });
      if (j.status == 'done' && !_navigated) {
        _navigated = true;
        _timer?.cancel();
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ResultScreen(jobId: j.id)));
      }
    } catch (e) {
      if (!mounted) return;
      _failCount++;
      // Sunucu model yüklerken birkaç saniye cevap veremeyebilir; hemen hata gösterme
      setState(() => _error = _failCount >= 6 ? Api.err(e) : (_failCount >= 3 ? 'Sunucu meşgul, bekleniyor…' : null));
    }
  }

  Future<void> _cancel() async {
    try {
      await Api.I.cancel(widget.jobId);
    } catch (e) {
      if (mounted) snack(context, Api.err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final j = _job;
    final pct = (j?.percent ?? 0) / 100.0;
    final finishedBad = j != null && (j.status == 'error' || j.status == 'cancelled');
    return Scaffold(
      appBar: AppBar(title: const Text('İşleniyor'), actions: const [BalanceChip()]),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(value: finishedBad ? 0 : pct, strokeWidth: 10, backgroundColor: Colors.white12, color: finishedBad ? Colors.redAccent : cs.primary),
                    Center(
                      child: Text('%${(pct * 100).round()}', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(j?.stage ?? 'Bağlanıyor…', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              if (j?.done != null && j?.total != null && j!.total! > 0)
                Text('${j.done} / ${j.total} kare', style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
              if (j?.etaSeconds != null) Text('Kalan ~${fmtSeconds(j!.etaSeconds!)}', style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
              if (j?.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(j!.error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent), textAlign: TextAlign.center),
                ),
              const Spacer(),
              Text('Telefonu bırakabilirsin; iş bilgisayarda devam eder.\nAna ekrandan "Son işler" ile geri dönebilirsin.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.55))),
              const SizedBox(height: 16),
              if (finishedBad)
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Geri dön'))
              else
                OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.close),
                  label: const Text('İptal et'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
