import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ── Blend mode list (text tracks) ────────────────────────────────────────────
const kVeTextBlendModes = [
  (label: 'Normal',    mode: BlendMode.srcOver),
  (label: 'Multiply',  mode: BlendMode.multiply),
  (label: 'Screen',    mode: BlendMode.screen),
  (label: 'Overlay',   mode: BlendMode.overlay),
  (label: 'Darken',    mode: BlendMode.darken),
  (label: 'Lighten',   mode: BlendMode.lighten),
  (label: 'Dodge',     mode: BlendMode.colorDodge),
  (label: 'Burn',      mode: BlendMode.colorBurn),
  (label: 'Hard Lt',   mode: BlendMode.hardLight),
  (label: 'Soft Lt',   mode: BlendMode.softLight),
  (label: 'Diff',      mode: BlendMode.difference),
  (label: 'Exclusion', mode: BlendMode.exclusion),
  (label: 'Add',       mode: BlendMode.plus),
];

// ── Blend-mode layer widget ───────────────────────────────────────────────────
/// Composites its child against everything drawn below it in the same canvas
/// using [blendMode].  Falls through to plain paint when mode is srcOver.
class VeBlendLayer extends SingleChildRenderObjectWidget {
  final BlendMode blendMode;
  const VeBlendLayer({super.key, required this.blendMode, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      VeBlendLayerRender(blendMode);

  @override
  void updateRenderObject(
      BuildContext context, VeBlendLayerRender renderObject) {
    renderObject.blendMode = blendMode;
  }
}

class VeBlendLayerRender extends RenderProxyBox {
  BlendMode _blendMode;
  VeBlendLayerRender(this._blendMode);

  BlendMode get blendMode => _blendMode;
  set blendMode(BlendMode v) {
    if (_blendMode == v) return;
    _blendMode = v;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_blendMode == BlendMode.srcOver) {
      super.paint(context, offset);
      return;
    }
    context.canvas.saveLayer(
      offset & size,
      Paint()..blendMode = _blendMode,
    );
    super.paint(context, offset);
    context.canvas.restore();
  }
}
