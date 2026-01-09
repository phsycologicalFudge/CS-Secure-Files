import 'file_entry.dart';

enum ClipboardAction { copy, move }

class FileClipboard {
  final ClipboardAction action;
  final List<FileEntry> items;

  FileClipboard(this.action, this.items);
}
