const fs = require('fs');
let content = fs.readFileSync('lib/features/scanner/presentation/signature_bottom_sheet.dart', 'utf-8');

// 1. Replace state variables
content = content.replace(
    /final List<List<Offset>> _strokes = \[\];\s*List<Offset>\? _currentStroke;/,
    "final _signatureController = _SignatureController();"
);

// 2. Replace _hasDrawing
content = content.replace(
    /bool get _hasDrawing =>[^;]+;/,
    "bool get _hasDrawing => _signatureController.hasDrawing;"
);

// 3. Replace _clearCanvas
content = content.replace(
    /void _clearCanvas\(\) => setState\(\(\) \{[^}]+\}\);/,
    "void _clearCanvas() { setState(() {}); _signatureController.clear(); }"
);

// 4. Remove _renderToPng
content = content.replace(
    /Future<Uint8List> _renderToPng[\s\S]*?return byteData!\.buffer\.asUint8List\(\);\s*\}/,
    ""
);

// 5. Update _confirmNewSignature
content = content.replace(
    "final pngBytes = await _renderToPng(canvasSize: size);",
    "final pngBytes = await _signatureController.toPngBytes();\n      if (pngBytes == null) throw Exception('توقيع فارغ');"
);

// 6. Listen to controller changes
content = content.replace(
    "void initState() {",
    "void initState() {\n    _signatureController.addListener(() { if(mounted) setState((){}); });"
);

content = content.replace(
    "Widget build(BuildContext context) {",
    "@override\n  void dispose() {\n    _signatureController.dispose();\n    super.dispose();\n  }\n\n  @override\n  Widget build(BuildContext context) {"
);


// 7. Update Canvas Widget
const canvasRegex = /child: GestureDetector\(\s*onPanStart: \(d\)[\s\S]*?child: CustomPaint\([\s\S]*?child: _hasDrawing[\s\S]*?Center\([\s\S]*?\),[\s\S]*?\),\s*\),\s*\),/;
const canvasNew = "child: _SignaturePadWidget(" +
"                            controller: _signatureController," +
"                            showHint: !_hasDrawing," +
"                            theme: theme," +
"                            palette: palette," +
"                          ),";
content = content.replace(canvasRegex, canvasNew);

// 8. Replace Painter
const painterRegex = /class _SignaturePainter extends CustomPainter \{[\s\S]*\}\s*$/;

let painterNew = fs.readFileSync('painter.txt', 'utf-8');
content = content.replace(painterRegex, painterNew);

fs.writeFileSync('lib/features/scanner/presentation/signature_bottom_sheet.dart', content);
