import 'package:flutter/material.dart';

const brandColors = <String, Color>{
  'mint': Color(0xff24997c),
  'blue': Color(0xff2563b8),
  'amber': Color(0xff946300),
  'purple': Color(0xff8250b5),
  'rose': Color(0xffba4169),
};
const brandNames = {
  'mint': '薄荷绿',
  'blue': '蓝色',
  'amber': '琥珀色',
  'purple': '紫色',
  'rose': '玫瑰色',
};
const codeThemeNames = {'classic': '经典彩色', 'ocean': '海洋蓝', 'dracula': '紫夜'};

@immutable
class CodePalette extends ThemeExtension<CodePalette> {
  final Color keyword,
      string,
      comment,
      number,
      variable,
      foreground,
      background;
  const CodePalette({
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.variable,
    required this.foreground,
    required this.background,
  });
  factory CodePalette.named(String name, bool dark) {
    if (name == 'ocean') {
      return CodePalette(
        keyword: Color(dark ? 0xff82baff : 0xff175cad),
        string: Color(dark ? 0xff8be5d1 : 0xff006858),
        comment: Color(dark ? 0xff8faeb9 : 0xff52676e),
        number: Color(dark ? 0xffffc68e : 0xff995000),
        variable: Color(dark ? 0xffd6aaff : 0xff773caa),
        foreground: Color(dark ? 0xffe1eff5 : 0xff1b3545),
        background: Color(dark ? 0xff102632 : 0xfff3f9fc),
      );
    }
    if (name == 'dracula') {
      return CodePalette(
        keyword: Color(dark ? 0xffff93d7 : 0xff9d2876),
        string: Color(dark ? 0xffe8ed96 : 0xff685a00),
        comment: Color(dark ? 0xffa6b0dc : 0xff586488),
        number: Color(dark ? 0xffbdabff : 0xff6740a7),
        variable: Color(dark ? 0xff91ebfb : 0xff006e80),
        foreground: Color(dark ? 0xfff3f0ff : 0xff30253d),
        background: Color(dark ? 0xff282638 : 0xfffaf5ff),
      );
    }
    return CodePalette(
      keyword: Color(dark ? 0xffffcc75 : 0xff956100),
      string: Color(dark ? 0xffb4dfa0 : 0xff306923),
      comment: Color(dark ? 0xff8dc49b : 0xff237333),
      number: Color(dark ? 0xffc2a2ff : 0xff733bb8),
      variable: Color(dark ? 0xffffb58c : 0xffa34d00),
      foreground: Color(dark ? 0xffe5e9ef : 0xff202630),
      background: Color(dark ? 0xff171e27 : 0xfffbfcfe),
    );
  }
  @override
  CodePalette copyWith({
    Color? keyword,
    Color? string,
    Color? comment,
    Color? number,
    Color? variable,
    Color? foreground,
    Color? background,
  }) => CodePalette(
    keyword: keyword ?? this.keyword,
    string: string ?? this.string,
    comment: comment ?? this.comment,
    number: number ?? this.number,
    variable: variable ?? this.variable,
    foreground: foreground ?? this.foreground,
    background: background ?? this.background,
  );
  @override
  CodePalette lerp(covariant CodePalette? other, double t) {
    if (other == null) return this;
    return CodePalette(
      keyword: Color.lerp(keyword, other.keyword, t)!,
      string: Color.lerp(string, other.string, t)!,
      comment: Color.lerp(comment, other.comment, t)!,
      number: Color.lerp(number, other.number, t)!,
      variable: Color.lerp(variable, other.variable, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      background: Color.lerp(background, other.background, t)!,
    );
  }
}
