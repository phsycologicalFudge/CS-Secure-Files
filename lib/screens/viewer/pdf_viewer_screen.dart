import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class PdfViewerScreen extends StatefulWidget {
  final String path;
  const PdfViewerScreen({super.key, required this.path});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfControllerPinch controller;

  @override
  void initState() {
    super.initState();
    controller = PdfControllerPinch(document: PdfDocument.openFile(widget.path));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          widget.path.split('/').last,
          style: TextStyle(color: colors.onSurface),
        ),
        iconTheme: IconThemeData(color: colors.onSurface),
      ),
      body: PdfViewPinch(
        controller: controller,
        backgroundDecoration: BoxDecoration(color: colors.background),
      ),
    );
  }
}
