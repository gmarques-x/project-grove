// Registers font files with macOS (persistent user scope) and reports any
// PostScript names that still aren't available afterwards.
//
// Usage: osascript -l JavaScript register-fonts.js [--verify] <font file>...
//   --verify  only check whether the fonts are active; register nothing
//
// Called by install-fonts.sh. Output: "checked=N missing=M [names...]"
ObjC.import('CoreText');
ObjC.import('Foundation');

function run(args) {
  var verifyOnly = args[0] === '--verify';
  var paths = verifyOnly ? args.slice(1) : args;
  var wanted = [];

  paths.forEach(function (p) {
    var url = $.NSURL.fileURLWithPath(p);
    if (!verifyOnly) {
      // 2 = persistent scope. Returns false if the font is already registered, which is fine.
      $.CTFontManagerRegisterFontsForURL(url, 2, null);
    }
    var descs = ObjC.castRefToObject($.CTFontManagerCreateFontDescriptorsFromURL(url));
    if (descs.isNil() || descs.count === 0) { wanted.push('(unreadable)' + p); return; }
    for (var i = 0; i < descs.count; i++) {
      // CTFontDescriptor is toll-free bridged to NSFontDescriptor.
      wanted.push(descs.objectAtIndex(i).postscriptName.js);
    }
  });

  var available = ObjC.deepUnwrap(ObjC.castRefToObject($.CTFontManagerCopyAvailablePostScriptNames()));
  var active = {};
  available.forEach(function (n) { active[n] = true; });
  var missing = wanted.filter(function (n) { return !active[n]; });
  return 'checked=' + wanted.length + ' missing=' + missing.length + (missing.length ? ' ' + missing.join(' ') : '');
}
