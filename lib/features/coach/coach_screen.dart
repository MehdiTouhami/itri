import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/page_title.dart';
import '../../core/widgets/primitives.dart';
import '../../data/coach/coach_client.dart';
import '../../domain/facts.dart';
import '../../state/providers.dart';

class _Msg {
  _Msg.user(this.text) : fromUser = true;
  _Msg.coach() : fromUser = false, text = '';

  final bool fromUser;
  String text;
  bool done = false;
  String? error;

  /// Figures in the reply that are not in the user's data; null if unchecked.
  List<String>? unverified;
}

/// One coach for both halves of the app. Every question carries the user's
/// exact numbers, and every answer is checked against them.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _messages = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _client = CoachClient();
  bool _busy = false;

  static const _debrief = 'Write my weekly debrief: what went well, what to watch, and one suggestion '
      'for next week. Cover both training and sleep, and keep it short.';
  static const _starters = [
    'How did I sleep this week?',
    'Should I train hard today?',
    'Why is my HRV where it is?',
    'Do late sessions affect my sleep?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    final consented = switch (ref.read(coachConsentProvider)) {
      AsyncData(:final value) => value,
      _ => false,
    };
    if (text.isEmpty || _busy || !consented) return;
    final facts = ref.read(factsProvider);

    final history = <(String, String)>[];
    for (var i = 0; i + 1 < _messages.length; i += 2) {
      final q = _messages[i], a = _messages[i + 1];
      if (q.fromUser && a.done && a.error == null) history.add((q.text, a.text));
    }

    final reply = _Msg.coach();
    setState(() {
      _messages
        ..add(_Msg.user(text))
        ..add(reply);
      _busy = true;
    });
    _input.clear();
    _scrollDown();

    try {
      await for (final token in _client.ask(text, history: history, facts: facts)) {
        if (!mounted) return;
        setState(() => reply.text += token);
        _scrollDown();
      }
      reply.text = reply.text.replaceAll('**', '').trim();
      if (facts != null) reply.unverified = unverifiedNumbers(reply.text, facts);
    } on CoachException catch (e) {
      reply.error = e.message;
    } catch (_) {
      reply.error = 'Something went wrong. Try again.';
    } finally {
      if (mounted) {
        setState(() {
          reply.done = true;
          _busy = false;
        });
        _scrollDown();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final ready = ref.watch(factsProvider) != null;
    final consented = switch (ref.watch(coachConsentProvider)) {
      AsyncData(:final value) => value,
      _ => false,
    };
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.lg, Sp.gutter, Sp.md),
              child: PageTitle(
                eyebrow: 'Training + recovery',
                title: 'COACH',
                tag: ready ? 'Your data attached' : 'Loading data',
                tagColor: ready ? t.gold : null,
              ),
            ),
            Expanded(
              child: !consented
                  ? _Consent(onAccept: () => ref.read(coachConsentProvider.notifier).accept())
                  : _messages.isEmpty
                  ? _Intro(onAsk: _send, debrief: _debrief, starters: _starters)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.sm, Sp.gutter, Sp.xl),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) => _Bubble(_messages[i]),
                    ),
            ),
            if (consented) _InputBar(controller: _input, busy: _busy, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onAsk, required this.debrief, required this.starters});
  final ValueChanged<String> onAsk;
  final String debrief;
  final List<String> starters;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, 0, Sp.gutter, Sp.xl),
      children: [
        Text(
          'Ask anything about your training and your nights. Answers use your exact numbers and '
          'published sleep and sports research, and every figure is checked against your data.',
          style: Tx.body(t, color: t.textMuted),
        ),
        const SizedBox(height: Sp.xl),
        Pressable(
          onTap: () => onAsk(debrief),
          child: Container(
            padding: const EdgeInsets.all(Sp.lg),
            decoration: BoxDecoration(
              border: Border.all(color: t.gold.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow('Weekly debrief', color: t.gold),
                      const SizedBox(height: Sp.xs),
                      Text('A short read on your week across training and sleep, with one suggestion.',
                          style: Tx.small(t, color: t.text)),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.md),
                Icon(Icons.arrow_forward_rounded, size: 18, color: t.gold),
              ],
            ),
          ),
        ),
        const SectionHeader('Try asking'),
        for (final s in starters)
          Pressable(
            onTap: () => onAsk(s),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: Sp.md),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Row(
                children: [
                  Expanded(child: Text(s, style: Tx.body(t))),
                  Icon(Icons.north_east_rounded, size: 14, color: t.textFaint),
                ],
              ),
            ),
          ),
        const SizedBox(height: Sp.lg),
        Text(
          'Not medical advice. For symptoms, illness or injury, see a doctor or physio.',
          style: Tx.small(t, color: t.textFaint),
        ),
      ],
    );
  }
}

/// Shown once, before anything is sent: what leaves the phone, where it goes,
/// and that the coach is not a clinician.
class _Consent extends StatelessWidget {
  const _Consent({required this.onAccept});
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    Widget para(String s) => Padding(
          padding: const EdgeInsets.only(bottom: Sp.md),
          child: Text(s, style: Tx.body(t, color: t.textMuted)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, 0, Sp.gutter, Sp.xl),
      children: [
        Eyebrow('Before you ask', color: t.gold),
        const SizedBox(height: Sp.md),
        para('To answer, Itri sends your recent training and sleep numbers to Google Gemini: dates, sports, '
            'heart rate, load, sleep scores and HRV. Not your name, your location or any GPS. Itri\'s own server '
            'passes them on and keeps nothing.'),
        para('On Gemini\'s free tier, Google may use what it receives to improve its products, and people may '
            'review it. Don\'t type anything into the coach you wouldn\'t want seen.'),
        para('The coach is not medical advice and can be wrong. For symptoms, illness, injury or anything that '
            'worries you, talk to a doctor or physio.'),
        const SizedBox(height: Sp.sm),
        Pressable(
          onTap: onAccept,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.text, borderRadius: BorderRadius.circular(4)),
            child: Text('I UNDERSTAND', style: Tx.eyebrow(t, color: t.ground)),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);
  final _Msg m;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: Sp.lg, bottom: Sp.sm, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
          decoration: BoxDecoration(
            color: t.raised,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(m.text, style: Tx.body(t)),
        ),
      );
    }
    final waiting = !m.done && m.text.isEmpty;
    final unverified = m.unverified;
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm, bottom: Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Itri', color: t.gold),
          const SizedBox(height: Sp.xs),
          if (m.error != null)
            Text(m.error!, style: Tx.body(t, color: t.down))
          else
            SelectableText(
              waiting ? 'Reading your data… (the first answer can take up to a minute)' : '${m.text}${m.done ? '' : ' ▍'}',
              style: Tx.body(t, color: waiting ? t.textFaint : t.text).copyWith(height: 1.5),
            ),
          if (m.done && unverified != null) ...[
            const SizedBox(height: Sp.sm),
            Text(
              unverified.isEmpty
                  ? '✓ Every figure above is in your data'
                  : 'Not found in your data: ${unverified.join(', ')}. Treat as estimates.',
              style: Tx.data(t, size: 10.5, color: unverified.isEmpty ? t.up : t.gold),
            ),
          ],
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.busy, required this.onSend});
  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.sm, Sp.sm, Sp.sm),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !busy,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: onSend,
              style: Tx.body(t),
              decoration: InputDecoration(
                hintText: busy ? 'Itri is answering…' : 'Ask the coach',
                hintStyle: Tx.body(t, color: t.textFaint),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            onPressed: busy ? null : () => onSend(controller.text),
            icon: Icon(Icons.arrow_upward_rounded, color: busy ? t.textFaint : t.gold),
            tooltip: 'Send',
          ),
        ],
      ),
    );
  }
}
