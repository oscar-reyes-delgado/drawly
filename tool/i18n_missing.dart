import 'dart:io';

/// Scans `lib/**/*.dart` for `tr('...', '...')` calls, extracts the English
/// (second) argument, and compares against the language maps in
/// `lib/core/i18n.dart`.
void main(List<String> args) {
  final asJson = args.contains('--json');
  final libDir = Directory('lib');
  final i18nFile = File('lib/core/i18n.dart');

  if (!libDir.existsSync() || !i18nFile.existsSync()) {
    stderr.writeln('Error: must be run from the repository root.');
    exit(0);
  }

  final usedKeys = <String>{};
  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in dartFiles) {
    final src = file.readAsStringSync();
    usedKeys.addAll(_extractTrEnglishKeys(src));
  }

  final i18nSrc = i18nFile.readAsStringSync();
  final langMaps = _extractExtraLanguageKeys(i18nSrc);

  final missingByLang = <String, List<String>>{};
  for (final entry in langMaps.entries) {
    final missing = usedKeys.difference(entry.value).toList()..sort();
    missingByLang[entry.key] = missing;
  }

  if (asJson) {
    final parts = <String>[];
    for (final entry in missingByLang.entries) {
      final items = entry.value.map(_jsonQuote).join(', ');
      parts.add('${_jsonQuote(entry.key)}: [$items]');
    }
    stdout.writeln('{${parts.join(', ')}}');
  } else {
    for (final entry in missingByLang.entries) {
      stdout.writeln('${entry.key}: ${entry.value.length}');
      for (final key in entry.value) {
        stdout.writeln('  $key');
      }
    }
  }
}

/// Extracts the second argument of every `tr('...', '...')` call in [src],
/// skipping comments and supporting escaped quotes, adjacent string literals,
/// multiline arguments, and calls nested inside `${...}`.
Set<String> _extractTrEnglishKeys(String src) {
  final keys = <String>{};
  final n = src.length;
  var i = 0;

  while (i < n) {
    final c = src.codeUnitAt(i);

    // Skip line and block comments
    if (c == 0x2F /* / */ && i + 1 < n) {
      final next = src.codeUnitAt(i + 1);
      if (next == 0x2F /* / */) {
        i += 2;
        while (i < n && src.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      if (next == 0x2A /* * */) {
        i += 2;
        while (i + 1 < n && !(src.codeUnitAt(i) == 0x2A && src.codeUnitAt(i + 1) == 0x2F)) {
          i++;
        }
        i += 2;
        continue;
      }
    }

    // Match `tr` identifier at word boundary
    if (c == 0x74 /* t */ &&
        i + 1 < n &&
        src.codeUnitAt(i + 1) == 0x72 /* r */ &&
        (i == 0 || !_isIdentPart(src.codeUnitAt(i - 1)) && src.codeUnitAt(i - 1) != 0x2E /* . */) &&
        (i + 2 >= n || !_isIdentPart(src.codeUnitAt(i + 2)))) {
      var j = _skipWsAndComments(src, i + 2);
      if (j < n && src.codeUnitAt(j) == 0x28 /* ( */) {
        j = _skipWsAndComments(src, j + 1);
        final arg1 = _readStringArg(src, j);
        if (arg1 != null) {
          j = _skipWsAndComments(src, arg1.$2);
          if (j < n && src.codeUnitAt(j) == 0x2C /* , */) {
            j = _skipWsAndComments(src, j + 1);
            final arg2 = _readStringArg(src, j);
            if (arg2 != null) {
              keys.add(arg2.$1);
              i = arg2.$2;
              continue;
            }
          }
        }
      }
    }

    i++;
  }

  return keys;
}

int _skipWsAndComments(String src, int start) {
  final n = src.length;
  var i = start;
  while (i < n) {
    final c = src.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
      continue;
    }
    if (c == 0x2F /* / */ && i + 1 < n) {
      final next = src.codeUnitAt(i + 1);
      if (next == 0x2F) {
        i += 2;
        while (i < n && src.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      if (next == 0x2A) {
        i += 2;
        while (i + 1 < n && !(src.codeUnitAt(i) == 0x2A && src.codeUnitAt(i + 1) == 0x2F)) {
          i++;
        }
        i += 2;
        continue;
      }
    }
    break;
  }
  return i;
}

/// Reads one or more adjacent string literals starting at [start].
(String, int)? _readStringArg(String src, int start) {
  final first = _readSingleString(src, start);
  if (first == null) return null;
  final buf = StringBuffer(first.$1);
  var i = first.$2;
  while (true) {
    final nextStart = _skipWsAndComments(src, i);
    final next = _readSingleString(src, nextStart);
    if (next == null) break;
    buf.write(next.$1);
    i = next.$2;
  }
  return (buf.toString(), i);
}

(String, int)? _readSingleString(String src, int start) {
  final n = src.length;
  if (start >= n) return null;
  var i = start;
  var raw = false;
  if (src.codeUnitAt(i) == 0x72 /* r */ && i + 1 < n) {
    final q = src.codeUnitAt(i + 1);
    if (q == 0x27 || q == 0x22) {
      raw = true;
      i++;
    }
  }
  final quote = src.codeUnitAt(i);
  if (quote != 0x27 /* ' */ && quote != 0x22 /* " */) return null;
  return _readStringLiteral(src, i, raw: raw);
}

bool _isIdentStart(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x24;

bool _isIdentPart(int c) => _isIdentStart(c) || (c >= 0x30 && c <= 0x39);

(String, int) _readStringLiteral(String src, int start, {required bool raw}) {
  final n = src.length;
  final quote = src.codeUnitAt(start);
  var i = start + 1;

  final isTriple =
      i + 1 < n && src.codeUnitAt(i) == quote && src.codeUnitAt(i + 1) == quote;
  if (isTriple) {
    i += 2;
  }

  final buf = StringBuffer();
  while (i < n) {
    final c = src.codeUnitAt(i);
    if (!raw && c == 0x5C /* \ */) {
      if (i + 1 < n) {
        final next = src.codeUnitAt(i + 1);
        switch (next) {
          case 0x6E:
            buf.write('\n');
          case 0x72:
            buf.write('\r');
          case 0x74:
            buf.write('\t');
          case 0x27:
            buf.write("'");
          case 0x22:
            buf.write('"');
          case 0x5C:
            buf.write(r'\');
          case 0x24:
            buf.write(r'$');
          default:
            buf.writeCharCode(next);
        }
        i += 2;
        continue;
      }
    }
    if (isTriple) {
      if (c == quote &&
          i + 2 < n &&
          src.codeUnitAt(i + 1) == quote &&
          src.codeUnitAt(i + 2) == quote) {
        i += 3;
        break;
      }
    } else if (c == quote) {
      i++;
      break;
    }
    buf.writeCharCode(c);
    i++;
  }
  return (buf.toString(), i);
}

/// Token types produced by the minimal Dart lexer.
enum _TokKind { ident, string, punct }

class _Tok {
  const _Tok(this.kind, this.text);
  final _TokKind kind;
  final String text;
}

List<_Tok> _tokenize(String src) {
  final tokens = <_Tok>[];
  final n = src.length;
  var i = 0;

  while (i < n) {
    i = _skipWsAndComments(src, i);
    if (i >= n) break;
    final c = src.codeUnitAt(i);

    final str = _readSingleString(src, i);
    if (str != null) {
      tokens.add(_Tok(_TokKind.string, str.$1));
      i = str.$2;
      continue;
    }

    if (_isIdentStart(c)) {
      final start = i;
      i++;
      while (i < n && _isIdentPart(src.codeUnitAt(i))) {
        i++;
      }
      tokens.add(_Tok(_TokKind.ident, src.substring(start, i)));
      continue;
    }

    tokens.add(_Tok(_TokKind.punct, src[i]));
    i++;
  }

  return tokens;
}

(String, int)? _readAdjacentStrings(List<_Tok> tokens, int index) {
  if (index >= tokens.length || tokens[index].kind != _TokKind.string) {
    return null;
  }
  final buf = StringBuffer(tokens[index].text);
  var i = index + 1;
  while (i < tokens.length && tokens[i].kind == _TokKind.string) {
    buf.write(tokens[i].text);
    i++;
  }
  return (buf.toString(), i);
}

/// Parses `_extra` in `lib/core/i18n.dart` and returns the set of existing keys
/// for each language code (e.g. `'pt'`, `'fr'`).
Map<String, Set<String>> _extractExtraLanguageKeys(String i18nSrc) {
  final tokens = _tokenize(i18nSrc);
  final result = <String, Set<String>>{};

  var i = 0;
  while (i < tokens.length) {
    if (tokens[i].kind == _TokKind.ident && tokens[i].text == '_extra') {
      break;
    }
    i++;
  }
  while (i < tokens.length &&
      !(tokens[i].kind == _TokKind.punct && tokens[i].text == '{')) {
    i++;
  }
  if (i >= tokens.length) return result;
  i++;

  var outerDepth = 1;
  while (i < tokens.length && outerDepth > 0) {
    final tok = tokens[i];
    if (tok.kind == _TokKind.punct && tok.text == '}') {
      outerDepth--;
      i++;
      continue;
    }
    if (outerDepth == 1 && tok.kind == _TokKind.string) {
      final langCode = tok.text;
      if (i + 2 < tokens.length &&
          tokens[i + 1].kind == _TokKind.punct &&
          tokens[i + 1].text == ':' &&
          tokens[i + 2].kind == _TokKind.punct &&
          tokens[i + 2].text == '{') {
        final langKeys = <String>{};
        i += 3;
        var innerDepth = 1;
        while (i < tokens.length && innerDepth > 0) {
          final inner = tokens[i];
          if (inner.kind == _TokKind.punct && inner.text == '{') {
            innerDepth++;
            i++;
            continue;
          }
          if (inner.kind == _TokKind.punct && inner.text == '}') {
            innerDepth--;
            i++;
            continue;
          }
          if (innerDepth == 1 && inner.kind == _TokKind.string) {
            final keyRes = _readAdjacentStrings(tokens, i)!;
            final afterKey = keyRes.$2;
            if (afterKey < tokens.length &&
                tokens[afterKey].kind == _TokKind.punct &&
                tokens[afterKey].text == ':') {
              langKeys.add(keyRes.$1);
              final valRes = _readAdjacentStrings(tokens, afterKey + 1);
              i = valRes != null ? valRes.$2 : afterKey + 1;
              continue;
            }
          }
          i++;
        }
        result[langCode] = langKeys;
        continue;
      }
    }
    i++;
  }

  return result;
}

String _jsonQuote(String s) {
  final buf = StringBuffer('"');
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    switch (c) {
      case 0x22:
        buf.write(r'\"');
      case 0x5C:
        buf.write(r'\\');
      case 0x08:
        buf.write(r'\b');
      case 0x0C:
        buf.write(r'\f');
      case 0x0A:
        buf.write(r'\n');
      case 0x0D:
        buf.write(r'\r');
      case 0x09:
        buf.write(r'\t');
      default:
        if (c < 0x20) {
          buf.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          buf.writeCharCode(c);
        }
    }
  }
  buf.write('"');
  return buf.toString();
}
