class OcrWord {
  final String text;
  final int left;
  final int top;
  final int right;
  final int bottom;

  const OcrWord({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  int get midX => (left + right) ~/ 2;
  int get midY => (top + bottom) ~/ 2;
  int get height => bottom - top;
}
