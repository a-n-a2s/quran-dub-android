import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../overlay/overlay_frame.dart';
import '../overlay/overlay_style.dart';
import '../overlay/overlay_timeline.dart';
import 'export_plan.dart';

/// طلب رسم صورة نص مقطع واحد (يوم 8).
class OverlayRenderJob {
  /// أبعاد الفيديو الناتج بالبكسل.
  final int width;
  final int height;
  final OverlayBand band;
  final OverlayItem item;
  final OverlayStyle style;

  const OverlayRenderJob({
    required this.width,
    required this.height,
    required this.band,
    required this.item,
    required this.style,
  });
}

/// بيرسم صور النص للتصدير **بنفس [AyahOverlayFrame] تبع المعاينة** (مش نسخة
/// منه): الويدجت بينبني بأبعاد الفيديو الحقيقية (1 بكسل منطقي = 1 بكسل
/// بالصورة)، وبنصوّر شريط الكتلة بس ([OverlayBand]) كـ PNG شفافة. الشفافية
/// (fade) ما بتنرسم هون: الصورة دايماً بشفافية 1، والـ Kotlin بيطبّق
/// [OverlayTimeline.opacityOf] لكل إطار (= نفس `Opacity` بالمعاينة).
///
/// لازم [OverlayRenderHost] يكون بشجرة الويدجت (مخفي، حجمه صفر) وقت الرسم.
class OverlayRenderController {
  _OverlayRenderHostState? _host;

  bool get isAttached => _host != null;

  Future<Uint8List> renderPng(OverlayRenderJob job) {
    final h = _host;
    if (h == null) {
      throw StateError('OverlayRenderHost مش بالشجرة');
    }
    return h._render(job);
  }
}

class OverlayRenderHost extends StatefulWidget {
  final OverlayRenderController controller;
  const OverlayRenderHost({super.key, required this.controller});

  @override
  State<OverlayRenderHost> createState() => _OverlayRenderHostState();
}

class _OverlayRenderHostState extends State<OverlayRenderHost> {
  final GlobalKey _boundary = GlobalKey();
  OverlayRenderJob? _job;
  Future<void> _queue = Future.value();

  @override
  void initState() {
    super.initState();
    widget.controller._host = this;
  }

  @override
  void didUpdateWidget(OverlayRenderHost old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._host = null;
      widget.controller._host = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller._host == this) widget.controller._host = null;
    super.dispose();
  }

  Future<Uint8List> _render(OverlayRenderJob job) {
    // طلب ورا طلب (ما في رسمتين بنفس الوقت).
    final c = Completer<Uint8List>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await _renderNow(job));
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  Future<Uint8List> _renderNow(OverlayRenderJob job) async {
    if (!mounted) throw StateError('OverlayRenderHost انشال');
    setState(() => _job = job);
    await WidgetsBinding.instance.endOfFrame;
    final ro = _boundary.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      throw StateError('ما لقينا مكان الرسم');
    }
    final image = await ro.toImage(pixelRatio: 1.0);
    try {
      if (image.width != job.width || image.height != job.band.height) {
        throw StateError(
            'حجم صورة النص ${image.width}x${image.height} بدل ${job.width}x${job.band.height}');
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('ما قدرنا نحوّل صورة النص لـ PNG');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    if (job == null) return const SizedBox.shrink();
    final w = job.width.toDouble();
    final bandH = job.band.height.toDouble();
    // حجمه على الشاشة صفر (مخفي)، بس بينرسم بطبقة لحاله (RepaintBoundary)
    // وبنصوّرها هي بس.
    return SizedBox.shrink(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: w,
          maxWidth: w,
          minHeight: bandH,
          maxHeight: bandH,
          child: RepaintBoundary(
            key: _boundary,
            child: OverlayBandView(job: job),
          ),
        ),
      ),
    );
  }
}

/// شريط الكتلة من [AyahOverlayFrame] بأبعاد الفيديو الحقيقية: نفس الإطار تبع
/// المعاينة بالضبط، مزاح لفوق بـ [OverlayBand.top] ومقصوص على ارتفاع الشريط.
class OverlayBandView extends StatelessWidget {
  final OverlayRenderJob job;
  const OverlayBandView({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final w = job.width.toDouble(), h = job.height.toDouble();
    return SizedBox(
      width: w,
      height: job.band.height.toDouble(),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: -job.band.top.toDouble(),
            width: w,
            height: h,
            child: IgnorePointer(
              child: AyahOverlayFrame(
                videoWidth: job.width,
                videoHeight: job.height,
                cue: OverlayCue(job.item, 1.0),
                tafsirMode: job.style.tafsirMode,
                font: job.style.font,
                color: job.style.color,
                shadow: job.style.shadow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
