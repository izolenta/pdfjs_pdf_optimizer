import 'dart:async';
import 'dart:io';
import 'dart:math';

final a2width = 1191;
final a2height = 1684;

Future main(List<String> arguments) async {
  if (arguments.length != 1) {
    print("Usage: pdf_optimizer <filename.pdf>");
    return;
  }
  print("Adjusting size");
  PdfData pdfData = await _getPdfData(arguments[0]);
  final dim1 = pdfData.pages.map((f) => f.dimensions.x).toList();
  dim1.sort();
  final scaleX = a2width / dim1.last;
  final dim2 = pdfData.pages.map((f) => f.dimensions.y).toList();
  dim1.sort();
  final scaleY = a2height / dim2.last;
  final scaleMin = min(scaleX, scaleY);
  if (scaleMin < 1) {
    await _separatePages(arguments[0], pdfData.pages.length);
    await _doResize(pdfData, scaleMin);
    await _concatenate(arguments[0], pdfData.pages.length);
  }
  else {
    print("...no need to adjust.");
  }
}

Future _concatenate(String filename, int pages) async {
  print("Concatenating pages");
  final processed = "${filename.substring(0, filename.length-4)}.PROCESSED.pdf";
  final files = ['-dBATCH', '-dNOPAUSE', '-q', '-sDEVICE=pdfwrite', '-dAutoRotatePages=/None', '-sOutputFile=$processed'];
  for (var i=1; i<=pages; i++) {
    files.add("split$i.pdf");
  }
  await Process.run('gs', files);
  for (var i=1; i<=pages; i++) {
//    await Process.run('rm', ['split$i.pdf']);
  }
}

Future _doResize(PdfData data, num scale) async {
  print("Scaling pages to A2");
  for (var i=1; i<=data.pages.length; i++) {
    final page = data.pages.firstWhere((p) => p.pageNum == i);
    print("=> scaling $i");
    await Process.run('./pdfscale.sh', ['-a', 'none', '-r','custom pt ${(page.dimensions.x*scale).round()} ${(page.dimensions.y*scale).round()}', 'split$i.pdf', 'split_scaled$i.pdf']);
    await Process.run('mv', ['split_scaled$i.pdf', 'split$i.pdf']);
  }
}

Future _separatePages(String filename, int pages) async {
  print("Separating pages");
  for (var i=1; i<=pages; i++) {
    await Process.run('gs', [
      '-sDEVICE=pdfwrite',
      '-dCompatibilityLevel=1.4',
      '-dNOPAUSE',
      '-dQUIET',
      '-dBATCH',
      '-dColorImageFilter=/DCTEncode',
      '-dColorConversionStrategy=/LeaveColorUnchange',
      '-dFirstPage=$i',
      '-dLastPage=$i',
      '-sOutputFile=split$i.pdf',
      '-dAutoRotatePages=/None',
      filename
    ]);
  }
}

Future<PdfData> _getPdfData(String filename) async {
  var pagesCount;
  var pdfData;
  await Process.run('pdfinfo', [filename]).then((ProcessResult results) {
    final info = results.stdout.toString().split("\n");
    var size;
    var optimized;
    for (var next in info) {
      final item = next.split(":");
      if (item[0].toLowerCase().trim() == "pages") {
        pagesCount = int.parse(item[1].trim());
      }
      if (item[0].toLowerCase().trim() == "file size") {
        size = int.parse(item[1].trim().substring(0, item[1].trim().indexOf(" ")));
      }
      if (item[0].toLowerCase().trim() == "optimized") {
        optimized = item[1].trim() == "yes";
      }
    }
    pdfData = new PdfData(optimized, size);
  });
  await Process.run('pdfinfo', ['-f', '1', '-l', '$pagesCount', filename]).then((ProcessResult results) {
    final info = results.stdout.toString().split("\n");
    for (var next in info) {
      final item = next.split(":");
      final name = item[0].replaceAll(new RegExp(r"\s+"), " ").toLowerCase();
      if (name.startsWith("page") && name.endsWith("size")) {
        final pageNum = int.parse(name.replaceAll(new RegExp(r"[^\d]"), ""));
        final sizes = item[1].trim().split(" ");
        pdfData.pages.add(new PdfPageData(pageNum, new Point(num.parse(sizes[0]), num.parse(sizes[2]))));
      }
    }
  });
  return pdfData;
}

class PdfData {
  final List<PdfPageData> pages = [];
  final bool optimized;
  final int size;

  PdfData(this.optimized, this.size);
}

class PdfPageData {
  final Point dimensions;
  final pageNum;
  PdfPageData(this.pageNum, this.dimensions);
}