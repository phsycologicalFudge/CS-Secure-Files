import 'package:flutter_riverpod/flutter_riverpod.dart';

// Holds a list of file names (for now, dummy data)
final fileListProvider = StateProvider<List<String>>((ref) => [
  'Documents',
  'Photos',
  'notes.txt',
  'report.pdf',
]);
