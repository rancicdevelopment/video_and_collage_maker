import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Cell data ────────────────────────────────────────────────────────────────

class CollageCellData {
  final String? filePath;
  final bool isVideo;
  final Duration duration;
  final Duration trimStart;
  final Duration trimEnd;
  final double volume;

  const CollageCellData({
    this.filePath,
    this.isVideo = true,
    this.duration = Duration.zero,
    this.trimStart = Duration.zero,
    this.trimEnd = Duration.zero,
    this.volume = 1.0,
  });

  bool get isEmpty => filePath == null;

  /// A GIF used as cell content: a non-video image whose file is a .gif.
  /// Rendered as an animated image and exported as a looping input.
  bool get isGif =>
      !isVideo && (filePath?.toLowerCase().endsWith('.gif') ?? false);

  CollageCellData copyWith({
    String? filePath,
    bool? isVideo,
    Duration? duration,
    Duration? trimStart,
    Duration? trimEnd,
    double? volume,
  }) =>
      CollageCellData(
        filePath: filePath ?? this.filePath,
        isVideo: isVideo ?? this.isVideo,
        duration: duration ?? this.duration,
        trimStart: trimStart ?? this.trimStart,
        trimEnd: trimEnd ?? this.trimEnd,
        volume: volume ?? this.volume,
      );
}

// ── Layout definition ─────────────────────────────────────────────────────────

class CollageLayoutDef {
  final String id;
  final int cellCount;
  final List<Rect> cells; // normalized 0..1
  final bool isShape;
  final bool isArtistic;

  const CollageLayoutDef({
    required this.id,
    required this.cellCount,
    required this.cells,
    this.isShape = false,
    this.isArtistic = false,
  });
}

// ── Rectangular layouts ───────────────────────────────────────────────────────

const kCollageLayouts = <CollageLayoutDef>[
  // 1 cell
  CollageLayoutDef(id: '1_full', cellCount: 1,
      cells: [Rect.fromLTRB(0,0,1,1)]),

  // 2 cells — existing
  CollageLayoutDef(id: '2_v_eq', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,.5,1), Rect.fromLTRB(.5,0,1,1)]),
  CollageLayoutDef(id: '2_h_eq', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,1,.5), Rect.fromLTRB(0,.5,1,1)]),
  CollageLayoutDef(id: '2_v_6040', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,.6,1), Rect.fromLTRB(.6,0,1,1)]),
  CollageLayoutDef(id: '2_v_4060', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,.4,1), Rect.fromLTRB(.4,0,1,1)]),
  CollageLayoutDef(id: '2_h_6040', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,1,.6), Rect.fromLTRB(0,.6,1,1)]),
  CollageLayoutDef(id: '2_v_7030', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,.7,1), Rect.fromLTRB(.7,0,1,1)]),

  // 2 cells — new
  CollageLayoutDef(id: '2_h_7030', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,1,.7), Rect.fromLTRB(0,.7,1,1)]),
  CollageLayoutDef(id: '2_h_4060', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,1,.4), Rect.fromLTRB(0,.4,1,1)]),
  CollageLayoutDef(id: '2_h_3070', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,1,.3), Rect.fromLTRB(0,.3,1,1)]),
  CollageLayoutDef(id: '2_v_3070', cellCount: 2,
      cells: [Rect.fromLTRB(0,0,.3,1), Rect.fromLTRB(.3,0,1,1)]),

  // 3 cells — existing
  CollageLayoutDef(id: '3_l1r2', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,.5,1),
    Rect.fromLTRB(.5,0,1,.5), Rect.fromLTRB(.5,.5,1,1)]),
  CollageLayoutDef(id: '3_r1l2', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,.5,.5), Rect.fromLTRB(0,.5,.5,1),
    Rect.fromLTRB(.5,0,1,1)]),
  CollageLayoutDef(id: '3_t1b2', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,1,.5),
    Rect.fromLTRB(0,.5,.5,1), Rect.fromLTRB(.5,.5,1,1)]),
  CollageLayoutDef(id: '3_b1t2', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,.5,.5), Rect.fromLTRB(.5,0,1,.5),
    Rect.fromLTRB(0,.5,1,1)]),
  CollageLayoutDef(id: '3_v_eq', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,1/3,1),
    Rect.fromLTRB(1/3,0,2/3,1),
    Rect.fromLTRB(2/3,0,1,1)]),
  CollageLayoutDef(id: '3_h_eq', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,1,1/3),
    Rect.fromLTRB(0,1/3,1,2/3),
    Rect.fromLTRB(0,2/3,1,1)]),
  CollageLayoutDef(id: '3_l2r1', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,.35,.5), Rect.fromLTRB(0,.5,.35,1),
    Rect.fromLTRB(.35,0,1,1)]),

  // 3 cells — new
  CollageLayoutDef(id: '3_t_big', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,1,.6),
    Rect.fromLTRB(0,.6,.5,1), Rect.fromLTRB(.5,.6,1,1)]),
  CollageLayoutDef(id: '3_b_big', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,.5,.4), Rect.fromLTRB(.5,0,1,.4),
    Rect.fromLTRB(0,.4,1,1)]),
  CollageLayoutDef(id: '3_l_big', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,.6,1),
    Rect.fromLTRB(.6,0,1,.5), Rect.fromLTRB(.6,.5,1,1)]),
  CollageLayoutDef(id: '3_r_big', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,.4,.5), Rect.fromLTRB(0,.5,.4,1),
    Rect.fromLTRB(.4,0,1,1)]),
  CollageLayoutDef(id: '3_h_mid_big', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,1,.15),
    Rect.fromLTRB(0,.15,1,.85),
    Rect.fromLTRB(0,.85,1,1)]),
  CollageLayoutDef(id: '3_v_mid_big', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,.15,1),
    Rect.fromLTRB(.15,0,.85,1),
    Rect.fromLTRB(.85,0,1,1)]),
  CollageLayoutDef(id: '3_tl_big', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,.65,.55), Rect.fromLTRB(.65,0,1,.55),
    Rect.fromLTRB(0,.55,1,1)]),
  CollageLayoutDef(id: '3_h_unequal', cellCount: 3, cells: [
    Rect.fromLTRB(0,0,1,.25),
    Rect.fromLTRB(0,.25,1,.65),
    Rect.fromLTRB(0,.65,1,1)]),

  // 4 cells — existing
  CollageLayoutDef(id: '4_grid', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.5,.5), Rect.fromLTRB(.5,0,1,.5),
    Rect.fromLTRB(0,.5,.5,1), Rect.fromLTRB(.5,.5,1,1)]),
  CollageLayoutDef(id: '4_l1r3', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.5,1),
    Rect.fromLTRB(.5,0,1,1/3), Rect.fromLTRB(.5,1/3,1,2/3),
    Rect.fromLTRB(.5,2/3,1,1)]),
  CollageLayoutDef(id: '4_r1l3', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.5,1/3), Rect.fromLTRB(0,1/3,.5,2/3),
    Rect.fromLTRB(0,2/3,.5,1),
    Rect.fromLTRB(.5,0,1,1)]),
  CollageLayoutDef(id: '4_t1b3', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,1,.5),
    Rect.fromLTRB(0,.5,1/3,1), Rect.fromLTRB(1/3,.5,2/3,1),
    Rect.fromLTRB(2/3,.5,1,1)]),
  CollageLayoutDef(id: '4_v_eq', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.25,1), Rect.fromLTRB(.25,0,.5,1),
    Rect.fromLTRB(.5,0,.75,1), Rect.fromLTRB(.75,0,1,1)]),

  // 4 cells — new
  CollageLayoutDef(id: '4_h_eq', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,1,.25), Rect.fromLTRB(0,.25,1,.5),
    Rect.fromLTRB(0,.5,1,.75), Rect.fromLTRB(0,.75,1,1)]),
  CollageLayoutDef(id: '4_b1t3', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,1/3,.5), Rect.fromLTRB(1/3,0,2/3,.5),
    Rect.fromLTRB(2/3,0,1,.5), Rect.fromLTRB(0,.5,1,1)]),
  CollageLayoutDef(id: '4_3col_mid2', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,1/3,1),
    Rect.fromLTRB(1/3,0,2/3,.5), Rect.fromLTRB(1/3,.5,2/3,1),
    Rect.fromLTRB(2/3,0,1,1)]),
  CollageLayoutDef(id: '4_3row_mid2', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,1,.25),
    Rect.fromLTRB(0,.25,.5,.75), Rect.fromLTRB(.5,.25,1,.75),
    Rect.fromLTRB(0,.75,1,1)]),
  CollageLayoutDef(id: '4_2x2_asym', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.4,.5), Rect.fromLTRB(.4,0,1,.5),
    Rect.fromLTRB(0,.5,.6,1), Rect.fromLTRB(.6,.5,1,1)]),
  CollageLayoutDef(id: '4_big_tl', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.65,.65), Rect.fromLTRB(.65,0,1,.65),
    Rect.fromLTRB(0,.65,.5,1), Rect.fromLTRB(.5,.65,1,1)]),
  CollageLayoutDef(id: '4_big_tr', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.4,.65), Rect.fromLTRB(.4,0,1,.65),
    Rect.fromLTRB(0,.65,.4,1), Rect.fromLTRB(.4,.65,1,1)]),
  CollageLayoutDef(id: '4_l2r2_asym', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.5,.35), Rect.fromLTRB(0,.35,.5,1),
    Rect.fromLTRB(.5,0,1,.65), Rect.fromLTRB(.5,.65,1,1)]),
  CollageLayoutDef(id: '4_sides_center', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,1,.15),
    Rect.fromLTRB(0,.15,.5,.85), Rect.fromLTRB(.5,.15,1,.85),
    Rect.fromLTRB(0,.85,1,1)]),
  CollageLayoutDef(id: '4_big_tl_r2_b1', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.5,.6),
    Rect.fromLTRB(.5,0,1,.3), Rect.fromLTRB(.5,.3,1,.6),
    Rect.fromLTRB(0,.6,1,1)]),
  CollageLayoutDef(id: '4_4col_asym', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.15,1), Rect.fromLTRB(.15,0,.5,1),
    Rect.fromLTRB(.5,0,.85,1), Rect.fromLTRB(.85,0,1,1)]),
  CollageLayoutDef(id: '4_center_wide', cellCount: 4, cells: [
    Rect.fromLTRB(0,0,.15,1),
    Rect.fromLTRB(.15,0,.85,.5), Rect.fromLTRB(.15,.5,.85,1),
    Rect.fromLTRB(.85,0,1,1)]),

  // 5 cells — existing
  CollageLayoutDef(id: '5_l1r4', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.5,1),
    Rect.fromLTRB(.5,0,1,.5),
    Rect.fromLTRB(.5,.5,.75,.75), Rect.fromLTRB(.75,.5,1,.75),
    Rect.fromLTRB(.5,.75,1,1)]),
  CollageLayoutDef(id: '5_3t2b', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,1/3,.5), Rect.fromLTRB(1/3,0,2/3,.5),
    Rect.fromLTRB(2/3,0,1,.5),
    Rect.fromLTRB(0,.5,.5,1), Rect.fromLTRB(.5,.5,1,1)]),
  CollageLayoutDef(id: '5_2t3b', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.5,.5), Rect.fromLTRB(.5,0,1,.5),
    Rect.fromLTRB(0,.5,1/3,1), Rect.fromLTRB(1/3,.5,2/3,1),
    Rect.fromLTRB(2/3,.5,1,1)]),

  // 5 cells — new
  CollageLayoutDef(id: '5_h_eq', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,1,.2), Rect.fromLTRB(0,.2,1,.4),
    Rect.fromLTRB(0,.4,1,.6), Rect.fromLTRB(0,.6,1,.8),
    Rect.fromLTRB(0,.8,1,1)]),
  CollageLayoutDef(id: '5_v_eq', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.2,1), Rect.fromLTRB(.2,0,.4,1),
    Rect.fromLTRB(.4,0,.6,1), Rect.fromLTRB(.6,0,.8,1),
    Rect.fromLTRB(.8,0,1,1)]),
  CollageLayoutDef(id: '5_l2r3', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.5,.5), Rect.fromLTRB(0,.5,.5,1),
    Rect.fromLTRB(.5,0,1,1/3), Rect.fromLTRB(.5,1/3,1,2/3),
    Rect.fromLTRB(.5,2/3,1,1)]),
  CollageLayoutDef(id: '5_l3r2', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.5,1/3), Rect.fromLTRB(0,1/3,.5,2/3),
    Rect.fromLTRB(0,2/3,.5,1),
    Rect.fromLTRB(.5,0,1,.5), Rect.fromLTRB(.5,.5,1,1)]),
  CollageLayoutDef(id: '5_2_1_2', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.5,.25), Rect.fromLTRB(.5,0,1,.25),
    Rect.fromLTRB(0,.25,1,.75),
    Rect.fromLTRB(0,.75,.5,1), Rect.fromLTRB(.5,.75,1,1)]),
  CollageLayoutDef(id: '5_big_tl', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.65,.6),
    Rect.fromLTRB(.65,0,1,.3), Rect.fromLTRB(.65,.3,1,.6),
    Rect.fromLTRB(0,.6,.5,1), Rect.fromLTRB(.5,.6,1,1)]),
  CollageLayoutDef(id: '5_t1_2_2', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,1,1/3),
    Rect.fromLTRB(0,1/3,.5,2/3), Rect.fromLTRB(.5,1/3,1,2/3),
    Rect.fromLTRB(0,2/3,.5,1), Rect.fromLTRB(.5,2/3,1,1)]),
  CollageLayoutDef(id: '5_r1l4', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.5,1),
    Rect.fromLTRB(.5,0,.75,.5), Rect.fromLTRB(.75,0,1,.5),
    Rect.fromLTRB(.5,.5,.75,1), Rect.fromLTRB(.75,.5,1,1)]),
  CollageLayoutDef(id: '5_h_unequal', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,1,.1), Rect.fromLTRB(0,.1,1,.35),
    Rect.fromLTRB(0,.35,1,.65),
    Rect.fromLTRB(0,.65,1,.9), Rect.fromLTRB(0,.9,1,1)]),
  CollageLayoutDef(id: '5_v_unequal', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.1,1), Rect.fromLTRB(.1,0,.35,1),
    Rect.fromLTRB(.35,0,.65,1),
    Rect.fromLTRB(.65,0,.9,1), Rect.fromLTRB(.9,0,1,1)]),
  CollageLayoutDef(id: '5_tl_big', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.6,.5),
    Rect.fromLTRB(.6,0,1,.25), Rect.fromLTRB(.6,.25,1,.5),
    Rect.fromLTRB(0,.5,.5,1), Rect.fromLTRB(.5,.5,1,1)]),
  CollageLayoutDef(id: '5_t4b1', cellCount: 5, cells: [
    Rect.fromLTRB(0,0,.5,.4), Rect.fromLTRB(.5,0,1,.4),
    Rect.fromLTRB(0,.4,.5,.7), Rect.fromLTRB(.5,.4,1,.7),
    Rect.fromLTRB(0,.7,1,1)]),

  // 6+ cells — existing
  CollageLayoutDef(id: '6_grid', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,1/3,.5), Rect.fromLTRB(1/3,0,2/3,.5),
    Rect.fromLTRB(2/3,0,1,.5),
    Rect.fromLTRB(0,.5,1/3,1), Rect.fromLTRB(1/3,.5,2/3,1),
    Rect.fromLTRB(2/3,.5,1,1)]),
  CollageLayoutDef(id: '6_v_eq', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,1/6,1), Rect.fromLTRB(1/6,0,2/6,1),
    Rect.fromLTRB(2/6,0,3/6,1), Rect.fromLTRB(3/6,0,4/6,1),
    Rect.fromLTRB(4/6,0,5/6,1), Rect.fromLTRB(5/6,0,1,1)]),

  // 6 cells — new
  CollageLayoutDef(id: '6_3r2c', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,.5,1/3), Rect.fromLTRB(.5,0,1,1/3),
    Rect.fromLTRB(0,1/3,.5,2/3), Rect.fromLTRB(.5,1/3,1,2/3),
    Rect.fromLTRB(0,2/3,.5,1), Rect.fromLTRB(.5,2/3,1,1)]),
  CollageLayoutDef(id: '6_t1b5', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,1,.45),
    Rect.fromLTRB(0,.45,.2,1), Rect.fromLTRB(.2,.45,.4,1),
    Rect.fromLTRB(.4,.45,.6,1), Rect.fromLTRB(.6,.45,.8,1),
    Rect.fromLTRB(.8,.45,1,1)]),
  CollageLayoutDef(id: '6_b1t5', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,.2,.55), Rect.fromLTRB(.2,0,.4,.55),
    Rect.fromLTRB(.4,0,.6,.55), Rect.fromLTRB(.6,0,.8,.55),
    Rect.fromLTRB(.8,0,1,.55),
    Rect.fromLTRB(0,.55,1,1)]),
  CollageLayoutDef(id: '6_l1r5', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,.45,1),
    Rect.fromLTRB(.45,0,1,1/3),
    Rect.fromLTRB(.45,1/3,.72,2/3), Rect.fromLTRB(.72,1/3,1,2/3),
    Rect.fromLTRB(.45,2/3,.72,1), Rect.fromLTRB(.72,2/3,1,1)]),
  CollageLayoutDef(id: '6_r1l5', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,.55,1/3),
    Rect.fromLTRB(0,1/3,.28,2/3), Rect.fromLTRB(.28,1/3,.55,2/3),
    Rect.fromLTRB(0,2/3,.28,1), Rect.fromLTRB(.28,2/3,.55,1),
    Rect.fromLTRB(.55,0,1,1)]),
  CollageLayoutDef(id: '6_big_tl', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,.65,.6),
    Rect.fromLTRB(.65,0,1,.3), Rect.fromLTRB(.65,.3,1,.6),
    Rect.fromLTRB(0,.6,1/3,1), Rect.fromLTRB(1/3,.6,2/3,1),
    Rect.fromLTRB(2/3,.6,1,1)]),
  CollageLayoutDef(id: '6_l_3r_b2', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,.5,.6),
    Rect.fromLTRB(.5,0,1,.2), Rect.fromLTRB(.5,.2,1,.4),
    Rect.fromLTRB(.5,.4,1,.6),
    Rect.fromLTRB(0,.6,.5,1), Rect.fromLTRB(.5,.6,1,1)]),
  CollageLayoutDef(id: '6_t1_ml1_mr2_b2', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,1,.2),
    Rect.fromLTRB(0,.2,.5,.7),
    Rect.fromLTRB(.5,.2,1,.45), Rect.fromLTRB(.5,.45,1,.7),
    Rect.fromLTRB(0,.7,.5,1), Rect.fromLTRB(.5,.7,1,1)]),
  CollageLayoutDef(id: '6_h_eq', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,1,1/6), Rect.fromLTRB(0,1/6,1,2/6),
    Rect.fromLTRB(0,2/6,1,3/6), Rect.fromLTRB(0,3/6,1,4/6),
    Rect.fromLTRB(0,4/6,1,5/6), Rect.fromLTRB(0,5/6,1,1)]),
  CollageLayoutDef(id: '6_t2_b4', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,.5,.4), Rect.fromLTRB(.5,0,1,.4),
    Rect.fromLTRB(0,.4,.25,1), Rect.fromLTRB(.25,.4,.5,1),
    Rect.fromLTRB(.5,.4,.75,1), Rect.fromLTRB(.75,.4,1,1)]),
  CollageLayoutDef(id: '6_mix_asym', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,.55,.45),
    Rect.fromLTRB(.55,0,1,.22), Rect.fromLTRB(.55,.22,1,.45),
    Rect.fromLTRB(0,.45,.22,1), Rect.fromLTRB(.22,.45,.55,1),
    Rect.fromLTRB(.55,.45,1,1)]),
  CollageLayoutDef(id: '6_l4r2', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,.35,.5), Rect.fromLTRB(.35,0,.7,.5),
    Rect.fromLTRB(0,.5,.35,1), Rect.fromLTRB(.35,.5,.7,1),
    Rect.fromLTRB(.7,0,1,.5), Rect.fromLTRB(.7,.5,1,1)]),
  CollageLayoutDef(id: '6_big_br', cellCount: 6, cells: [
    Rect.fromLTRB(0,0,1/3,.4), Rect.fromLTRB(1/3,0,2/3,.4),
    Rect.fromLTRB(2/3,0,1,.4),
    Rect.fromLTRB(0,.4,.35,1), Rect.fromLTRB(.35,.4,.65,1),
    Rect.fromLTRB(.65,.4,1,1)]),

  // 7 cells
  CollageLayoutDef(id: '7_3t4b', cellCount: 7, cells: [
    Rect.fromLTRB(0,0,1/3,.5), Rect.fromLTRB(1/3,0,2/3,.5),
    Rect.fromLTRB(2/3,0,1,.5),
    Rect.fromLTRB(0,.5,.25,1), Rect.fromLTRB(.25,.5,.5,1),
    Rect.fromLTRB(.5,.5,.75,1), Rect.fromLTRB(.75,.5,1,1)]),
  CollageLayoutDef(id: '7_4t3b', cellCount: 7, cells: [
    Rect.fromLTRB(0,0,.25,.5), Rect.fromLTRB(.25,0,.5,.5),
    Rect.fromLTRB(.5,0,.75,.5), Rect.fromLTRB(.75,0,1,.5),
    Rect.fromLTRB(0,.5,1/3,1), Rect.fromLTRB(1/3,.5,2/3,1),
    Rect.fromLTRB(2/3,.5,1,1)]),
  CollageLayoutDef(id: '7_h_eq', cellCount: 7, cells: [
    Rect.fromLTRB(0,0,1,1/7), Rect.fromLTRB(0,1/7,1,2/7),
    Rect.fromLTRB(0,2/7,1,3/7), Rect.fromLTRB(0,3/7,1,4/7),
    Rect.fromLTRB(0,4/7,1,5/7), Rect.fromLTRB(0,5/7,1,6/7),
    Rect.fromLTRB(0,6/7,1,1)]),

  // 8 cells
  CollageLayoutDef(id: '8_2r4c', cellCount: 8, cells: [
    Rect.fromLTRB(0,0,.25,.5), Rect.fromLTRB(.25,0,.5,.5),
    Rect.fromLTRB(.5,0,.75,.5), Rect.fromLTRB(.75,0,1,.5),
    Rect.fromLTRB(0,.5,.25,1), Rect.fromLTRB(.25,.5,.5,1),
    Rect.fromLTRB(.5,.5,.75,1), Rect.fromLTRB(.75,.5,1,1)]),
  CollageLayoutDef(id: '8_h_eq', cellCount: 8, cells: [
    Rect.fromLTRB(0,0,1,1/8), Rect.fromLTRB(0,1/8,1,2/8),
    Rect.fromLTRB(0,2/8,1,3/8), Rect.fromLTRB(0,3/8,1,4/8),
    Rect.fromLTRB(0,4/8,1,5/8), Rect.fromLTRB(0,5/8,1,6/8),
    Rect.fromLTRB(0,6/8,1,7/8), Rect.fromLTRB(0,7/8,1,1)]),

  // 9 cells
  CollageLayoutDef(id: '9_3x3', cellCount: 9, cells: [
    Rect.fromLTRB(0,0,1/3,1/3), Rect.fromLTRB(1/3,0,2/3,1/3),
    Rect.fromLTRB(2/3,0,1,1/3),
    Rect.fromLTRB(0,1/3,1/3,2/3), Rect.fromLTRB(1/3,1/3,2/3,2/3),
    Rect.fromLTRB(2/3,1/3,1,2/3),
    Rect.fromLTRB(0,2/3,1/3,1), Rect.fromLTRB(1/3,2/3,2/3,1),
    Rect.fromLTRB(2/3,2/3,1,1)]),

  // 10 cells
  CollageLayoutDef(id: '10_2x5', cellCount: 10, cells: [
    Rect.fromLTRB(0,0,.2,.5), Rect.fromLTRB(.2,0,.4,.5),
    Rect.fromLTRB(.4,0,.6,.5), Rect.fromLTRB(.6,0,.8,.5),
    Rect.fromLTRB(.8,0,1,.5),
    Rect.fromLTRB(0,.5,.2,1), Rect.fromLTRB(.2,.5,.4,1),
    Rect.fromLTRB(.4,.5,.6,1), Rect.fromLTRB(.6,.5,.8,1),
    Rect.fromLTRB(.8,.5,1,1)]),
];

// ── Shape layouts (single clip over the background colour) ────────────────────

// Shape layouts render through the artistic pipeline: one full-canvas cell
// whose clip path comes from kArtisticCellPaths (via shapePathForId).
const kShapeLayouts = <CollageLayoutDef>[
  CollageLayoutDef(id: 'shape_diamond',  cellCount: 1, cells: [Rect.fromLTRB(0,0,1,1)], isShape: true, isArtistic: true),
  CollageLayoutDef(id: 'shape_circle',   cellCount: 1, cells: [Rect.fromLTRB(0,0,1,1)], isShape: true, isArtistic: true),
  CollageLayoutDef(id: 'shape_triangle', cellCount: 1, cells: [Rect.fromLTRB(0,0,1,1)], isShape: true, isArtistic: true),
  CollageLayoutDef(id: 'shape_hexagon',  cellCount: 1, cells: [Rect.fromLTRB(0,0,1,1)], isShape: true, isArtistic: true),
  CollageLayoutDef(id: 'shape_star5',    cellCount: 1, cells: [Rect.fromLTRB(0,0,1,1)], isShape: true, isArtistic: true),
  CollageLayoutDef(id: 'shape_star6',    cellCount: 1, cells: [Rect.fromLTRB(0,0,1,1)], isShape: true, isArtistic: true),
  CollageLayoutDef(id: 'shape_star8',    cellCount: 1, cells: [Rect.fromLTRB(0,0,1,1)], isShape: true, isArtistic: true),
  CollageLayoutDef(id: 'shape_blob',     cellCount: 1, cells: [Rect.fromLTRB(0,0,1,1)], isShape: true, isArtistic: true),
];

// Ids of all single-clip shape layouts (used to register their clip paths).
const kShapeLayoutIds = [
  'shape_diamond', 'shape_circle', 'shape_triangle', 'shape_hexagon',
  'shape_star5', 'shape_star6', 'shape_star8', 'shape_blob',
];

// ── Shape path builders ───────────────────────────────────────────────────────

Path shapePathForId(String id, Size size) {
  final w = size.width, h = size.height;
  final cx = w / 2, cy = h / 2;
  switch (id) {
    case 'shape_diamond':
      return Path()
        ..moveTo(cx, h * 0.05)
        ..lineTo(w * 0.95, cy)
        ..lineTo(cx, h * 0.95)
        ..lineTo(w * 0.05, cy)
        ..close();
    case 'shape_circle':
      return Path()..addOval(Rect.fromLTWH(w * 0.05, h * 0.05, w * 0.9, h * 0.9));
    case 'shape_triangle':
      return Path()
        ..moveTo(cx, h * 0.05)
        ..lineTo(w * 0.95, h * 0.95)
        ..lineTo(w * 0.05, h * 0.95)
        ..close();
    case 'shape_hexagon':
      return _regularPolygon(cx, cy, cx * 0.88, 6, -math.pi / 6);
    case 'shape_star5':
      return _star(cx, cy, cx * 0.88, cx * 0.4, 5);
    case 'shape_star6':
      return _star(cx, cy, cx * 0.88, cx * 0.45, 6);
    case 'shape_star8':
      return _star(cx, cy, cx * 0.88, cx * 0.55, 8);
    case 'shape_blob':
      return Path()
        ..moveTo(w * .5, h * .08)
        ..cubicTo(w * .80, h * .02, w * .97, h * .24, w * .92, h * .50)
        ..cubicTo(w * .88, h * .76, w * .72, h * .96, w * .47, h * .93)
        ..cubicTo(w * .21, h * .90, w * .03, h * .71, w * .08, h * .44)
        ..cubicTo(w * .12, h * .19, w * .26, h * .12, w * .5, h * .08)
        ..close();
    default:
      return Path()..addRect(Rect.fromLTWH(0, 0, w, h));
  }
}

Path _regularPolygon(double cx, double cy, double r, int n, double startAngle) {
  final path = Path();
  for (int i = 0; i < n; i++) {
    final angle = startAngle + i * 2 * math.pi / n;
    final x = cx + r * math.cos(angle);
    final y = cy + r * math.sin(angle);
    if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
  }
  return path..close();
}

Path _star(double cx, double cy, double outer, double inner, int points) {
  final path = Path();
  for (int i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final angle = -math.pi / 2 + i * math.pi / points;
    final x = cx + r * math.cos(angle);
    final y = cy + r * math.sin(angle);
    if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
  }
  return path..close();
}

// ── Artistic layouts ──────────────────────────────────────────────────────────

// For artistic layouts, cells contains full-canvas Rect repeated cellCount times.
// Actual clip shapes come from kArtisticCellPaths.
final List<CollageLayoutDef> kArtisticLayouts = [
  // 2-cell artistic
  CollageLayoutDef(
    id: 'art_2_diag_nw_se', cellCount: 2, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(
    id: 'art_2_diag_ne_sw', cellCount: 2, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(
    id: 'art_2_v_book', cellCount: 2, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(
    id: 'art_2_h_book', cellCount: 2, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // book fold — pages spread wider at bottom (V gap at bottom)
  CollageLayoutDef(id: 'art_2_book_down', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // book fold — pages spread wider at top (V gap at top)
  CollageLayoutDef(id: 'art_2_book_up', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // horizontal parallelogram split — right side higher
  CollageLayoutDef(id: 'art_2_para_h_r1', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // horizontal parallelogram split — left side higher
  CollageLayoutDef(id: 'art_2_para_h_l1', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // horizontal parallelogram — 70/30, right side higher
  CollageLayoutDef(id: 'art_2_para_h_r2', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // horizontal parallelogram — 30/70, left side higher
  CollageLayoutDef(id: 'art_2_para_h_l2', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // large diamond overlay on background
  CollageLayoutDef(id: 'art_2_diamond', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // smaller diamond overlay
  CollageLayoutDef(id: 'art_2_diamond_sm', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // vertical S-curve split (wide wave)
  CollageLayoutDef(id: 'art_2_wave_v1', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // vertical S-curve split (narrow wave)
  CollageLayoutDef(id: 'art_2_wave_v2', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // horizontal S-curve split direction A
  CollageLayoutDef(id: 'art_2_wave_h1', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // horizontal S-curve split direction B
  CollageLayoutDef(id: 'art_2_wave_h2', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // circle split vertically (left + right semicircles)
  CollageLayoutDef(id: 'art_2_circle_lh', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // circle split horizontally (top + bottom semicircles)
  CollageLayoutDef(id: 'art_2_circle_tb', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // two separate circles side by side
  CollageLayoutDef(id: 'art_2_two_circles_h', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // two separate circles stacked vertically
  CollageLayoutDef(id: 'art_2_two_circles_v', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // circle with diagonal cut (top-left / bottom-right)
  CollageLayoutDef(id: 'art_2_circle_diag1', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // circle with diagonal cut (top-right / bottom-left)
  CollageLayoutDef(id: 'art_2_circle_diag2', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // vertical parallelogram — narrow left + wide right
  CollageLayoutDef(id: 'art_2_para_v_nl', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // vertical parallelogram — wide left + narrow right
  CollageLayoutDef(id: 'art_2_para_v_wn', cellCount: 2, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),

  // 3-cell artistic
  CollageLayoutDef(
    id: 'art_3_diag_v', cellCount: 3, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(
    id: 'art_3_diag_h', cellCount: 3, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(
    id: 'art_3_fan', cellCount: 3, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(
    id: 'art_3_inv_fan', cellCount: 3, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),

  // 3 vertical book pages
  CollageLayoutDef(id: 'art_3_v_book', cellCount: 3, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // 3 regions divided by S-curves
  CollageLayoutDef(id: 'art_3_wave_v', cellCount: 3, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // 3 cells fanning from left center
  CollageLayoutDef(id: 'art_3_x_left', cellCount: 3, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // 3 cells fanning from right center
  CollageLayoutDef(id: 'art_3_x_right', cellCount: 3, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // isometric cube — top, left and right faces
  CollageLayoutDef(id: 'art_3_cube', cellCount: 3, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),

  // 4-cell artistic
  CollageLayoutDef(
    id: 'art_4_x', cellCount: 4, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
            Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(
    id: 'art_4_diag', cellCount: 4, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
            Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(
    id: 'art_4_h_diag', cellCount: 4, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
            Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(
    id: 'art_4_corner_tris', cellCount: 4, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
            Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),

  // 4 horizontal book pages
  CollageLayoutDef(id: 'art_4_h_book', cellCount: 4, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
              Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // 4 circles in corners
  CollageLayoutDef(id: 'art_4_circles', cellCount: 4, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
              Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),

  // 5-cell artistic
  CollageLayoutDef(id: 'art_5_fan', cellCount: 5, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
              Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(id: 'art_5_diag', cellCount: 5, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
              Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  CollageLayoutDef(id: 'art_5_h_diag', cellCount: 5, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
              Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),

  // 6-cell artistic
  CollageLayoutDef(
    id: 'art_6_diag', cellCount: 6, isArtistic: true,
    cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
            Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
            Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // 6 triangles from center (star arrangement)
  CollageLayoutDef(id: 'art_6_x', cellCount: 6, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
              Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
  // 6 diagonal horizontal strips
  CollageLayoutDef(id: 'art_6_h_diag', cellCount: 6, isArtistic: true,
      cells: [Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1),
              Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1), Rect.fromLTRB(0,0,1,1)]),
];

// ── Artistic path builders ────────────────────────────────────────────────────

/// Path builder for adjustable artistic layouts. [o] holds the layout's
/// normalized divider offsets (all 0 = original layout).
typedef ArtPathBuilder = Path Function(Size s, List<double> o);

/// A draggable handle that adjusts one (or two) offset parameters of an
/// artistic layout.
///
/// axis: 0 = vertical divider (drag left/right), 1 = horizontal divider
/// (drag up/down), 2 = free point (drag both axes).
/// [x]/[y] is the handle's base position (normalized 0..1); [px]/[py] are the
/// indices into the layout's offset list for the x / y axis (-1 = fixed).
class ArtHandleDef {
  final int axis;
  final double x, y;
  final int px, py;

  const ArtHandleDef.vertical(this.x, int param, {this.y = 0.5})
      : axis = 0, px = param, py = -1;
  const ArtHandleDef.horizontal(this.y, int param, {this.x = 0.5})
      : axis = 1, px = -1, py = param;
  const ArtHandleDef.point(this.x, this.y, int paramX, int paramY)
      : axis = 2, px = paramX, py = paramY;
}

/// Number of offset parameters a layout uses (0 = not adjustable).
int artParamCount(String id) {
  final handles = kArtisticHandles[id];
  if (handles == null) return 0;
  var count = 0;
  for (final h in handles) {
    if (h.px >= 0 && h.px + 1 > count) count = h.px + 1;
    if (h.py >= 0 && h.py + 1 > count) count = h.py + 1;
  }
  return count;
}

// Large enough for the layout with the most parameters (art_4_corner_tris: 8).
const List<double> kArtZeroOffsets = [0, 0, 0, 0, 0, 0, 0, 0];

final Map<String, List<ArtHandleDef>> kArtisticHandles = {
  'art_2_diag_nw_se': const [ArtHandleDef.vertical(.5, 0)],
  'art_2_diag_ne_sw': const [ArtHandleDef.vertical(.5, 0)],
  'art_2_v_book':     const [ArtHandleDef.vertical(.5, 0)],
  'art_2_h_book':     const [ArtHandleDef.horizontal(.5, 0)],
  'art_2_book_down':  const [ArtHandleDef.vertical(.5, 0)],
  'art_2_book_up':    const [ArtHandleDef.vertical(.5, 0)],
  'art_2_para_h_r1':  const [ArtHandleDef.horizontal(.5, 0)],
  'art_2_para_h_l1':  const [ArtHandleDef.horizontal(.5, 0)],
  'art_2_para_h_r2':  const [ArtHandleDef.horizontal(.7, 0)],
  'art_2_para_h_l2':  const [ArtHandleDef.horizontal(.3, 0)],
  'art_2_wave_v1':    const [ArtHandleDef.vertical(.5, 0)],
  'art_2_wave_v2':    const [ArtHandleDef.vertical(.5, 0)],
  'art_2_wave_h1':    const [ArtHandleDef.horizontal(.5, 0)],
  'art_2_wave_h2':    const [ArtHandleDef.horizontal(.5, 0)],
  'art_2_para_v_nl':  const [ArtHandleDef.vertical(.25, 0)],
  'art_2_para_v_wn':  const [ArtHandleDef.vertical(.75, 0)],
  'art_3_diag_v': const [
    ArtHandleDef.vertical(.335, 0),
    ArtHandleDef.vertical(.665, 1),
  ],
  'art_3_diag_h': const [
    ArtHandleDef.horizontal(.335, 0),
    ArtHandleDef.horizontal(.665, 1),
  ],
  'art_3_fan': const [
    ArtHandleDef.vertical(.365, 0, y: .1),
    ArtHandleDef.vertical(.635, 1, y: .1),
  ],
  'art_3_inv_fan': const [
    ArtHandleDef.vertical(.365, 0, y: .9),
    ArtHandleDef.vertical(.635, 1, y: .9),
  ],
  'art_3_v_book': const [
    ArtHandleDef.vertical(.325, 0),
    ArtHandleDef.vertical(.7, 1),
  ],
  'art_3_wave_v': const [
    ArtHandleDef.vertical(.38, 0),
    ArtHandleDef.vertical(.65, 1),
  ],
  'art_3_x_left':  const [ArtHandleDef.vertical(.5, 0)],
  'art_3_x_right': const [ArtHandleDef.vertical(.5, 0)],
  'art_3_cube':    const [ArtHandleDef.point(.5, .48, 0, 1)],
  'art_4_x': const [ArtHandleDef.point(.5, .5, 0, 1)],
  'art_4_diag': const [
    ArtHandleDef.vertical(.25, 0),
    ArtHandleDef.vertical(.51, 1),
    ArtHandleDef.vertical(.75, 2),
  ],
  'art_4_h_diag': const [
    ArtHandleDef.horizontal(.25, 0),
    ArtHandleDef.horizontal(.51, 1),
    ArtHandleDef.horizontal(.75, 2),
  ],
  'art_4_corner_tris': const [
    ArtHandleDef.point(.5, .4, 0, 1),
    ArtHandleDef.point(.6, .5, 2, 3),
    ArtHandleDef.point(.5, .6, 4, 5),
    ArtHandleDef.point(.4, .5, 6, 7),
  ],
  'art_4_h_book': const [
    ArtHandleDef.horizontal(.27, 0),
    ArtHandleDef.horizontal(.53, 1),
    ArtHandleDef.horizontal(.77, 2),
  ],
  'art_5_fan': const [
    ArtHandleDef.vertical(.248, 0, y: .1),
    ArtHandleDef.vertical(.446, 1, y: .1),
    ArtHandleDef.vertical(.644, 2, y: .1),
    ArtHandleDef.vertical(.842, 3, y: .1),
  ],
  'art_5_diag': const [
    ArtHandleDef.vertical(.195, 0),
    ArtHandleDef.vertical(.415, 1),
    ArtHandleDef.vertical(.615, 2),
    ArtHandleDef.vertical(.815, 3),
  ],
  'art_5_h_diag': const [
    ArtHandleDef.horizontal(.195, 0),
    ArtHandleDef.horizontal(.415, 1),
    ArtHandleDef.horizontal(.585, 2),
    ArtHandleDef.horizontal(.805, 3),
  ],
  'art_6_diag': const [
    ArtHandleDef.vertical(.16, 0),
    ArtHandleDef.vertical(.343, 1),
    ArtHandleDef.vertical(.525, 2),
    ArtHandleDef.vertical(.708, 3),
    ArtHandleDef.vertical(.891, 4),
  ],
  'art_6_x': const [ArtHandleDef.point(.5, .5, 0, 1)],
  'art_6_h_diag': const [
    ArtHandleDef.horizontal(.16, 0),
    ArtHandleDef.horizontal(.343, 1),
    ArtHandleDef.horizontal(.525, 2),
    ArtHandleDef.horizontal(.708, 3),
    ArtHandleDef.horizontal(.891, 4),
  ],
};

final Map<String, List<ArtPathBuilder>> kArtisticAdjustablePaths = {
  // 2-cell: diagonal NW-SE split
  'art_2_diag_nw_se': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w * (.6 + o[0]), 0)
        ..lineTo(w * (.4 + o[0]), h)
        ..lineTo(0, h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.6 + o[0]), 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * (.4 + o[0]), h)
        ..close();
    },
  ],

  // 2-cell: diagonal NE-SW split
  'art_2_diag_ne_sw': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w * (.4 + o[0]), 0)
        ..lineTo(w * (.6 + o[0]), h)
        ..lineTo(0, h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.4 + o[0]), 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * (.6 + o[0]), h)
        ..close();
    },
  ],

  // 2-cell: vertical book fold
  'art_2_v_book': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w * (.5 + o[0]), 0)
        ..lineTo(w * (.46 + o[0]), h)
        ..lineTo(0, h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.5 + o[0]), 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * (.54 + o[0]), h)
        ..close();
    },
  ],

  // 2-cell: horizontal book fold
  'art_2_h_book': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h * (.46 + o[0]))
        ..lineTo(0, h * (.5 + o[0]))
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, h * (.5 + o[0]))
        ..lineTo(w, h * (.54 + o[0]))
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
    },
  ],

  // 2-cell: V-book (pages spread wider at bottom)
  'art_2_book_down': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w*(.5+o[0]),0)..lineTo(w*(.45+o[0]),h)..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.5+o[0]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.55+o[0]),h)..close();
    },
  ],

  // 2-cell: inverted V-book (pages spread wider at top)
  'art_2_book_up': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w*(.45+o[0]),0)..lineTo(w*(.5+o[0]),h)..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.55+o[0]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.5+o[0]),h)..close();
    },
  ],

  // 2-cell: horizontal parallelogram split — right side higher (50/50)
  'art_2_para_h_r1': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w,0)..lineTo(w,h*(.46+o[0]))..lineTo(0,h*(.54+o[0]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.54+o[0]))..lineTo(w,h*(.46+o[0]))..lineTo(w,h)..lineTo(0,h)..close();
    },
  ],

  // 2-cell: horizontal parallelogram split — left side higher (50/50)
  'art_2_para_h_l1': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w,0)..lineTo(w,h*(.54+o[0]))..lineTo(0,h*(.46+o[0]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.46+o[0]))..lineTo(w,h*(.54+o[0]))..lineTo(w,h)..lineTo(0,h)..close();
    },
  ],

  // 2-cell: horizontal parallelogram — 70/30, right higher
  'art_2_para_h_r2': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w,0)..lineTo(w,h*(.65+o[0]))..lineTo(0,h*(.75+o[0]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.75+o[0]))..lineTo(w,h*(.65+o[0]))..lineTo(w,h)..lineTo(0,h)..close();
    },
  ],

  // 2-cell: horizontal parallelogram — 30/70, left higher
  'art_2_para_h_l2': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w,0)..lineTo(w,h*(.25+o[0]))..lineTo(0,h*(.35+o[0]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.35+o[0]))..lineTo(w,h*(.25+o[0]))..lineTo(w,h)..lineTo(0,h)..close();
    },
  ],

  // 2-cell: vertical S-curve split (wide wave)
  'art_2_wave_v1': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0,0)..lineTo(w*(.5+o[0]),0)
        ..cubicTo(w*(.2+o[0]),h*.33, w*(.8+o[0]),h*.67, w*(.5+o[0]),h)
        ..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w*(.5+o[0]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.5+o[0]),h)
        ..cubicTo(w*(.8+o[0]),h*.67, w*(.2+o[0]),h*.33, w*(.5+o[0]),0)..close();
    },
  ],

  // 2-cell: vertical S-curve split (narrow wave)
  'art_2_wave_v2': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0,0)..lineTo(w*(.5+o[0]),0)
        ..cubicTo(w*(.3+o[0]),h*.33, w*(.7+o[0]),h*.67, w*(.5+o[0]),h)
        ..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w*(.5+o[0]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.5+o[0]),h)
        ..cubicTo(w*(.7+o[0]),h*.67, w*(.3+o[0]),h*.33, w*(.5+o[0]),0)..close();
    },
  ],

  // 2-cell: horizontal S-curve split (direction A)
  'art_2_wave_h1': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0,0)..lineTo(w,0)..lineTo(w,h*(.5+o[0]))
        ..cubicTo(w*.67,h*(.2+o[0]), w*.33,h*(.8+o[0]), 0,h*(.5+o[0]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0,h*(.5+o[0]))
        ..cubicTo(w*.33,h*(.8+o[0]), w*.67,h*(.2+o[0]), w,h*(.5+o[0]))
        ..lineTo(w,h)..lineTo(0,h)..close();
    },
  ],

  // 2-cell: horizontal S-curve split (direction B)
  'art_2_wave_h2': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0,0)..lineTo(w,0)..lineTo(w,h*(.5+o[0]))
        ..cubicTo(w*.67,h*(.8+o[0]), w*.33,h*(.2+o[0]), 0,h*(.5+o[0]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0,h*(.5+o[0]))
        ..cubicTo(w*.33,h*(.2+o[0]), w*.67,h*(.8+o[0]), w,h*(.5+o[0]))
        ..lineTo(w,h)..lineTo(0,h)..close();
    },
  ],

  // 2-cell: vertical parallelogram — narrow left + wide right
  'art_2_para_v_nl': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w*(.28+o[0]),0)..lineTo(w*(.22+o[0]),h)..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.28+o[0]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.22+o[0]),h)..close();
    },
  ],

  // 2-cell: vertical parallelogram — wide left + narrow right
  'art_2_para_v_wn': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w*(.72+o[0]),0)..lineTo(w*(.78+o[0]),h)..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.72+o[0]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.78+o[0]),h)..close();
    },
  ],

  // 3-cell: diagonal vertical strips
  'art_3_diag_v': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w * (.37 + o[0]), 0)
        ..lineTo(w * (.3 + o[0]), h)
        ..lineTo(0, h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.37 + o[0]), 0)
        ..lineTo(w * (.7 + o[1]), 0)
        ..lineTo(w * (.63 + o[1]), h)
        ..lineTo(w * (.3 + o[0]), h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.7 + o[1]), 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * (.63 + o[1]), h)
        ..close();
    },
  ],

  // 3-cell: diagonal horizontal strips
  'art_3_diag_h': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h * (.3 + o[0]))
        ..lineTo(0, h * (.37 + o[0]))
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, h * (.37 + o[0]))
        ..lineTo(w, h * (.3 + o[0]))
        ..lineTo(w, h * (.7 + o[1]))
        ..lineTo(0, h * (.63 + o[1]))
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, h * (.63 + o[1]))
        ..lineTo(w, h * (.7 + o[1]))
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
    },
  ],

  // 3-cell: fan (converging to bottom center)
  'art_3_fan': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w * (.35 + o[0]), 0)
        ..lineTo(w * .5, h)
        ..lineTo(0, h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.35 + o[0]), 0)
        ..lineTo(w * (.65 + o[1]), 0)
        ..lineTo(w * .5, h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.65 + o[1]), 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * .5, h)
        ..close();
    },
  ],

  // 3-cell: inverted fan (converging to top center)
  'art_3_inv_fan': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w * .5, 0)
        ..lineTo(w * (.35 + o[0]), h)
        ..lineTo(0, h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * .5, 0)
        ..lineTo(w * (.65 + o[1]), h)
        ..lineTo(w * (.35 + o[0]), h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * .5, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * (.65 + o[1]), h)
        ..close();
    },
  ],

  // 3-cell: 3 vertical book pages (slight slant)
  'art_3_v_book': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w*(.35+o[0]),0)..lineTo(w*(.30+o[0]),h)..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.35+o[0]),0)..lineTo(w*(.68+o[1]),0)..lineTo(w*(.72+o[1]),h)..lineTo(w*(.30+o[0]),h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.68+o[1]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.72+o[1]),h)..close();
    },
  ],

  // 3-cell: S-curve wave splits (vertical)
  'art_3_wave_v': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0,0)..lineTo(w*(.38+o[0]),0)
        ..cubicTo(w*(.18+o[0]),h*.33, w*(.58+o[0]),h*.67, w*(.38+o[0]),h)
        ..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w*(.38+o[0]),0)..lineTo(w*(.65+o[1]),0)
        ..cubicTo(w*(.45+o[1]),h*.33, w*(.85+o[1]),h*.67, w*(.65+o[1]),h)
        ..lineTo(w*(.38+o[0]),h)
        ..cubicTo(w*(.58+o[0]),h*.67, w*(.18+o[0]),h*.33, w*(.38+o[0]),0)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w*(.65+o[1]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.65+o[1]),h)
        ..cubicTo(w*(.85+o[1]),h*.67, w*(.45+o[1]),h*.33, w*(.65+o[1]),0)..close();
    },
  ],

  // 3-cell: left strip + two triangles on right (X-left)
  'art_3_x_left': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w*(.55+o[0]),0)..lineTo(w*(.45+o[0]),h)..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.55+o[0]),0)..lineTo(w,0)..lineTo(w*(.45+o[0]),h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w,0)..lineTo(w,h)..lineTo(w*(.45+o[0]),h)..close();
    },
  ],

  // 3-cell: two triangles on left + right strip (X-right)
  'art_3_x_right': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w*(.55+o[0]),0)..lineTo(w*(.55+o[0]),h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(0,h)..lineTo(w*(.55+o[0]),h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.55+o[0]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.45+o[0]),h)..close();
    },
  ],

  // 3-cell: isometric cube (top + left + right faces, centre corner draggable)
  'art_3_cube': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.48 + o[1]);
      return Path()
        ..moveTo(w * .5, h * .08)
        ..lineTo(w * .92, h * .28)
        ..lineTo(cx, cy)
        ..lineTo(w * .08, h * .28)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.48 + o[1]);
      return Path()
        ..moveTo(w * .08, h * .28)
        ..lineTo(cx, cy)
        ..lineTo(w * .5, h * .92)
        ..lineTo(w * .08, h * .72)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.48 + o[1]);
      return Path()
        ..moveTo(cx, cy)
        ..lineTo(w * .92, h * .28)
        ..lineTo(w * .92, h * .72)
        ..lineTo(w * .5, h * .92)
        ..close();
    },
  ],

  // 4-cell: X (4 triangles meeting at center)
  'art_4_x': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(0, 0)..lineTo(w, 0)..lineTo(cx, cy)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(w, 0)..lineTo(w, h)..lineTo(cx, cy)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(w, h)..lineTo(0, h)..lineTo(cx, cy)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(0, h)..lineTo(0, 0)..lineTo(cx, cy)..close();
    },
  ],

  // 4-cell: diagonal vertical strips
  'art_4_diag': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w * (.28 + o[0]), 0)
        ..lineTo(w * (.22 + o[0]), h)
        ..lineTo(0, h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.28 + o[0]), 0)
        ..lineTo(w * (.54 + o[1]), 0)
        ..lineTo(w * (.48 + o[1]), h)
        ..lineTo(w * (.22 + o[0]), h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.54 + o[1]), 0)
        ..lineTo(w * (.78 + o[2]), 0)
        ..lineTo(w * (.72 + o[2]), h)
        ..lineTo(w * (.48 + o[1]), h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.78 + o[2]), 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * (.72 + o[2]), h)
        ..close();
    },
  ],

  // 4-cell: diagonal horizontal strips
  'art_4_h_diag': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h * (.22 + o[0]))
        ..lineTo(0, h * (.28 + o[0]))
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, h * (.28 + o[0]))
        ..lineTo(w, h * (.22 + o[0]))
        ..lineTo(w, h * (.48 + o[1]))
        ..lineTo(0, h * (.54 + o[1]))
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, h * (.54 + o[1]))
        ..lineTo(w, h * (.48 + o[1]))
        ..lineTo(w, h * (.72 + o[2]))
        ..lineTo(0, h * (.78 + o[2]))
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, h * (.78 + o[2]))
        ..lineTo(w, h * (.72 + o[2]))
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
    },
  ],

  // 4-cell: corner triangles (diamond gap in center)
  'art_4_corner_tris': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w * (.5 + o[0]), h * (.4 + o[1]))
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * (.6 + o[2]), h * (.5 + o[3]))
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, h)
        ..lineTo(w, h)
        ..lineTo(w * (.5 + o[4]), h * (.6 + o[5]))
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(0, h)
        ..lineTo(w * (.4 + o[6]), h * (.5 + o[7]))
        ..close();
    },
  ],

  // 4-cell: 4 horizontal book pages (slight slant)
  'art_4_h_book': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w,0)..lineTo(w,h*(.26+o[0]))..lineTo(0,h*(.28+o[0]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.28+o[0]))..lineTo(w,h*(.26+o[0]))..lineTo(w,h*(.52+o[1]))..lineTo(0,h*(.54+o[1]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.54+o[1]))..lineTo(w,h*(.52+o[1]))..lineTo(w,h*(.76+o[2]))..lineTo(0,h*(.78+o[2]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.78+o[2]))..lineTo(w,h*(.76+o[2]))..lineTo(w,h)..lineTo(0,h)..close();
    },
  ],

  // 5-cell: fan converging to bottom center
  'art_5_fan': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w*(.22+o[0]),0)..lineTo(w*.5,h)..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.22+o[0]),0)..lineTo(w*(.44+o[1]),0)..lineTo(w*.5,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.44+o[1]),0)..lineTo(w*(.66+o[2]),0)..lineTo(w*.5,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.66+o[2]),0)..lineTo(w*(.88+o[3]),0)..lineTo(w*.5,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.88+o[3]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*.5,h)..close();
    },
  ],

  // 5-cell: 5 diagonal vertical strips
  'art_5_diag': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w*(.22+o[0]),0)..lineTo(w*(.17+o[0]),h)..lineTo(0,h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.22+o[0]),0)..lineTo(w*(.44+o[1]),0)..lineTo(w*(.39+o[1]),h)..lineTo(w*(.17+o[0]),h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.44+o[1]),0)..lineTo(w*(.64+o[2]),0)..lineTo(w*(.59+o[2]),h)..lineTo(w*(.39+o[1]),h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.64+o[2]),0)..lineTo(w*(.84+o[3]),0)..lineTo(w*(.79+o[3]),h)..lineTo(w*(.59+o[2]),h)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(w*(.84+o[3]),0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*(.79+o[3]),h)..close();
    },
  ],

  // 5-cell: 5 diagonal horizontal strips
  'art_5_h_diag': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w,0)..lineTo(w,h*(.17+o[0]))..lineTo(0,h*(.22+o[0]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.22+o[0]))..lineTo(w,h*(.17+o[0]))..lineTo(w,h*(.39+o[1]))..lineTo(0,h*(.44+o[1]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.44+o[1]))..lineTo(w,h*(.39+o[1]))..lineTo(w,h*(.61+o[2]))..lineTo(0,h*(.56+o[2]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.56+o[2]))..lineTo(w,h*(.61+o[2]))..lineTo(w,h*(.83+o[3]))..lineTo(0,h*(.78+o[3]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.78+o[3]))..lineTo(w,h*(.83+o[3]))..lineTo(w,h)..lineTo(0,h)..close();
    },
  ],

  // 6-cell: X (6 triangles, 3 per diagonal half)
  'art_6_x': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(0,0)..lineTo(w*.5,0)..lineTo(cx,cy)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(w*.5,0)..lineTo(w,0)..lineTo(cx,cy)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(w,0)..lineTo(w,h)..lineTo(cx,cy)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(w,h)..lineTo(w*.5,h)..lineTo(cx,cy)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(w*.5,h)..lineTo(0,h)..lineTo(cx,cy)..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      final cx = w * (.5 + o[0]), cy = h * (.5 + o[1]);
      return Path()..moveTo(0,h)..lineTo(0,0)..lineTo(cx,cy)..close();
    },
  ],

  // 6-cell: 6 diagonal horizontal strips
  'art_6_h_diag': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,0)..lineTo(w,0)..lineTo(w,h*(.135+o[0]))..lineTo(0,h*(.185+o[0]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.185+o[0]))..lineTo(w,h*(.135+o[0]))..lineTo(w,h*(.318+o[1]))..lineTo(0,h*(.368+o[1]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.368+o[1]))..lineTo(w,h*(.318+o[1]))..lineTo(w,h*(.5+o[2]))..lineTo(0,h*(.55+o[2]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.55+o[2]))..lineTo(w,h*(.5+o[2]))..lineTo(w,h*(.683+o[3]))..lineTo(0,h*(.733+o[3]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.733+o[3]))..lineTo(w,h*(.683+o[3]))..lineTo(w,h*(.866+o[4]))..lineTo(0,h*(.916+o[4]))..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()..moveTo(0,h*(.916+o[4]))..lineTo(w,h*(.866+o[4]))..lineTo(w,h)..lineTo(0,h)..close();
    },
  ],

  // 6-cell: diagonal vertical strips
  'art_6_diag': [
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(0, 0)
        ..lineTo(w * (.185 + o[0]), 0)
        ..lineTo(w * (.135 + o[0]), h)
        ..lineTo(0, h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.185 + o[0]), 0)
        ..lineTo(w * (.368 + o[1]), 0)
        ..lineTo(w * (.318 + o[1]), h)
        ..lineTo(w * (.135 + o[0]), h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.368 + o[1]), 0)
        ..lineTo(w * (.55 + o[2]), 0)
        ..lineTo(w * (.5 + o[2]), h)
        ..lineTo(w * (.318 + o[1]), h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.55 + o[2]), 0)
        ..lineTo(w * (.733 + o[3]), 0)
        ..lineTo(w * (.683 + o[3]), h)
        ..lineTo(w * (.5 + o[2]), h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.733 + o[3]), 0)
        ..lineTo(w * (.916 + o[4]), 0)
        ..lineTo(w * (.866 + o[4]), h)
        ..lineTo(w * (.683 + o[3]), h)
        ..close();
    },
    (Size s, List<double> o) {
      final w = s.width, h = s.height;
      return Path()
        ..moveTo(w * (.916 + o[4]), 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * (.866 + o[4]), h)
        ..close();
    },
  ],
};

// Artistic layouts whose shapes have no meaningful linear divider
// (circle / diamond overlays and single-clip shape layouts) — these stay fixed.
final Map<String, List<Path Function(Size)>> _kArtisticStaticPaths = {
  // Single-clip shape layouts: media clipped to the shape over the bg colour.
  for (final id in kShapeLayoutIds)
    id: [(Size s) => shapePathForId(id, s)],

  // 2-cell: large diamond overlay on background
  'art_2_diamond': [
    (Size s) => Path()..addRect(Rect.fromLTWH(0, 0, s.width, s.height)),
    (Size s) {
      final w = s.width, h = s.height, cx = w/2, cy = h/2;
      return Path()..moveTo(cx,h*.05)..lineTo(w*.95,cy)..lineTo(cx,h*.95)..lineTo(w*.05,cy)..close();
    },
  ],

  // 2-cell: smaller diamond overlay
  'art_2_diamond_sm': [
    (Size s) => Path()..addRect(Rect.fromLTWH(0, 0, s.width, s.height)),
    (Size s) {
      final w = s.width, h = s.height, cx = w/2, cy = h/2;
      return Path()..moveTo(cx,h*.18)..lineTo(w*.82,cy)..lineTo(cx,h*.82)..lineTo(w*.18,cy)..close();
    },
  ],

  // 2-cell: circle split vertically (left + right semicircles)
  'art_2_circle_lh': [
    (Size s) {
      final cx = s.width/2, cy = s.height/2;
      final r = math.min(s.width, s.height) * .45;
      return Path()
        ..moveTo(cx, cy - r)
        ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r),
                -math.pi/2, -math.pi, false)
        ..close();
    },
    (Size s) {
      final cx = s.width/2, cy = s.height/2;
      final r = math.min(s.width, s.height) * .45;
      return Path()
        ..moveTo(cx, cy - r)
        ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r),
                -math.pi/2, math.pi, false)
        ..close();
    },
  ],

  // 2-cell: circle split horizontally (top + bottom semicircles)
  'art_2_circle_tb': [
    (Size s) {
      final cx = s.width/2, cy = s.height/2;
      final r = math.min(s.width, s.height) * .45;
      return Path()
        ..moveTo(cx - r, cy)
        ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r),
                math.pi, -math.pi, false)
        ..close();
    },
    (Size s) {
      final cx = s.width/2, cy = s.height/2;
      final r = math.min(s.width, s.height) * .45;
      return Path()
        ..moveTo(cx - r, cy)
        ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r),
                math.pi, math.pi, false)
        ..close();
    },
  ],

  // 2-cell: two separate full circles side by side
  'art_2_two_circles_h': [
    (Size s) => Path()..addOval(Rect.fromCircle(
        center: Offset(s.width*.28, s.height*.5), radius: s.width*.22)),
    (Size s) => Path()..addOval(Rect.fromCircle(
        center: Offset(s.width*.72, s.height*.5), radius: s.width*.22)),
  ],

  // 2-cell: two separate full circles stacked
  'art_2_two_circles_v': [
    (Size s) => Path()..addOval(Rect.fromCircle(
        center: Offset(s.width*.5, s.height*.28), radius: s.height*.22)),
    (Size s) => Path()..addOval(Rect.fromCircle(
        center: Offset(s.width*.5, s.height*.72), radius: s.height*.22)),
  ],

  // 2-cell: circle with diagonal cut (top-left / bottom-right halves)
  'art_2_circle_diag1': [
    (Size s) {
      final cx = s.width/2, cy = s.height/2;
      final r = math.min(s.width, s.height) * .45;
      final circle = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      final half = Path()..moveTo(0,0)..lineTo(s.width,0)..lineTo(0,s.height)..close();
      return Path.combine(PathOperation.intersect, circle, half);
    },
    (Size s) {
      final cx = s.width/2, cy = s.height/2;
      final r = math.min(s.width, s.height) * .45;
      final circle = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      final half = Path()..moveTo(s.width,0)..lineTo(s.width,s.height)..lineTo(0,s.height)..close();
      return Path.combine(PathOperation.intersect, circle, half);
    },
  ],

  // 2-cell: circle with diagonal cut (top-right / bottom-left halves)
  'art_2_circle_diag2': [
    (Size s) {
      final cx = s.width/2, cy = s.height/2;
      final r = math.min(s.width, s.height) * .45;
      final circle = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      final half = Path()..moveTo(0,0)..lineTo(s.width,0)..lineTo(s.width,s.height)..close();
      return Path.combine(PathOperation.intersect, circle, half);
    },
    (Size s) {
      final cx = s.width/2, cy = s.height/2;
      final r = math.min(s.width, s.height) * .45;
      final circle = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      final half = Path()..moveTo(0,0)..lineTo(0,s.height)..lineTo(s.width,s.height)..close();
      return Path.combine(PathOperation.intersect, circle, half);
    },
  ],

  // 4-cell: 4 circles in 2x2 grid
  'art_4_circles': [
    (Size s) => Path()..addOval(Rect.fromCircle(
        center: Offset(s.width*.27, s.height*.27), radius: s.width*.22)),
    (Size s) => Path()..addOval(Rect.fromCircle(
        center: Offset(s.width*.73, s.height*.27), radius: s.width*.22)),
    (Size s) => Path()..addOval(Rect.fromCircle(
        center: Offset(s.width*.27, s.height*.73), radius: s.width*.22)),
    (Size s) => Path()..addOval(Rect.fromCircle(
        center: Offset(s.width*.73, s.height*.73), radius: s.width*.22)),
  ],
};

// All artistic layouts with their default (offset-0) shapes — used by layout
// thumbnails and anywhere the current editor offsets are not available.
final Map<String, List<Path Function(Size)>> kArtisticCellPaths = {
  ..._kArtisticStaticPaths,
  for (final e in kArtisticAdjustablePaths.entries)
    e.key: [
      for (final b in e.value) (Size s) => b(s, kArtZeroOffsets),
    ],
};

/// True if [layoutId] is rendered through the artistic/shape clip pipeline
/// (i.e. it has per-cell clip paths rather than plain rectangles).
bool layoutHasArtisticPaths(String layoutId) =>
    kArtisticCellPaths.containsKey(layoutId);

/// Clip path of cell [index] for artistic / shape layout [layoutId], honouring
/// the current handle [offsets] (pass an empty list for the default shape).
Path artisticCellPath(
    String layoutId, int index, Size size, List<double> offsets) {
  final adjustable = kArtisticAdjustablePaths[layoutId];
  if (adjustable != null && index < adjustable.length) {
    return adjustable[index](
        size, offsets.isEmpty ? kArtZeroOffsets : offsets);
  }
  final fixed = kArtisticCellPaths[layoutId];
  if (fixed != null && index < fixed.length) return fixed[index](size);
  return Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
}
