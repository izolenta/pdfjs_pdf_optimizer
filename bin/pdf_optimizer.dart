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
  final scaleMin = num.parse(min(scaleX, scaleY).toStringAsFixed(2));
  var tempName = "${arguments[0].substring(0, arguments[0].length-4)}.PROCESSED.pdf";
  await Process.run('cp', ['${arguments[0]}', '$tempName']);
  if (scaleMin < 1) {
    print("Scaling factor: $scaleMin");
    bool samePages =
        pdfData.pages.map((f) => f.dimensions.x).toList().reduce(min) == pdfData.pages.first.dimensions.x
            && pdfData.pages.map((f) => f.dimensions.x).toList().reduce(max) == pdfData.pages.first.dimensions.x
            && pdfData.pages.map((f) => f.dimensions.y).toList().reduce(min) == pdfData.pages.first.dimensions.y
            && pdfData.pages.map((f) => f.dimensions.y).toList().reduce(max) == pdfData.pages.first.dimensions.y;
    if (!samePages) {
      print("Pages have different sizes, need to separate");
      await _separatePages(tempName, pdfData.pages.length);
      await _doResizePages(pdfData, scaleMin);
      await _concatenate(tempName, pdfData.pages.length);
    }
    else {
      print("Pages have same size, just resizing");
      await _doResizeFile(tempName, pdfData.pages.first.dimensions, scaleMin);
    }
    print("Downsampling images: $tempName");
    await _downsample(tempName);
  }
  else {
    print("...no need to adjust.");
  }
}

Future _downsample(String file) async {
  final args = [
    '-dColorImageDownsampleType=/Bicubic',
    '-dColorImageResolution=150',
    '-dGrayImageDownsampleType=/Bicubic',
    '-dGrayImageResolution=150',
    '-dMonoImageDownsampleType=/Bicubic',
    '-dMonoImageResolution=150',
    '-dPDFSETTINGS=/ebook',
    '-dBATCH',
    '-dNOPAUSE',
    '-q',
    '-sDEVICE=pdfwrite',
    '-dAutoRotatePages=/None',
    '-sOutputFile=$file.new',
    file
  ];
  await Process.run('gs', args).then((ProcessResult res) => print(res.stdout));
  await Process.run('mv', ['$file.new', '$file']);
}

Future _concatenate(String filename, int pages) async {
  print("Concatenating pages");
  final processed = "1_${filename}";
  final args = [
    '-dBATCH',
    '-dNOPAUSE',
    '-q',
    '-sDEVICE=pdfwrite',
    '-dAutoRotatePages=/None',
    '-sOutputFile=$processed',
  ];
  for (var i=1; i<=pages; i++) {
    args.add("split$i.pdf");
  }
  await Process.run('gs', args);
  for (var i=1; i<=pages; i++) {
    await Process.run('rm', ['split$i.pdf']);
  }
  await Process.run('mv', ['$processed', '$filename']);
}

Future _doResizePages(PdfData data, num scale) async {
  for (var i=1; i<=data.pages.length; i++) {
    final page = data.pages.firstWhere((p) => p.pageNum == i);
    print("=> scaling $i");
    await _doResizeFile("split$i.pdf", page.dimensions, scale);
  }
}

Future _doResizeFile(String file, Point size, num scale) async {
  await Process.run('./pdfscale.sh', [
    '-a',
    'none',
    '-r',
    'custom pt ${(size.x*scale).round()} ${(size.y*scale).round()}',
    '-s',
    '1.05',
    '$file',
    '$file.scaled.pdf'
  ]);
  await Process.run('mv', ['$file.scaled.pdf', '$file']);
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