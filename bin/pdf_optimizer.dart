import 'dart:async';
import 'dart:io';
import 'dart:math';

final downscaleTo = 9000000; //9mpix is fast enough
final threshold = downscaleTo * 1.3;

Future main(List<String> arguments) async {
  if (arguments.length != 1) {
    print("Usage: pdf_optimizer <filename.pdf>");
    return;
  }
  PdfData pdfData = await _getPdfData(arguments[0]);
  bool needToConvert = false;
  int needPpi = 999;
  bool force = false;
  for (var img in pdfData.images) {
    if (img.colorSpace == 'cmyk') {
      needToConvert = true;
      force = true;
    }
    if (img.mpix > threshold) {
      needToConvert = true;
      final scale = downscaleTo/img.mpix;
      final ppi = (img.dpi * scale).floor();
      if (needPpi > ppi) {
        needPpi = ppi;
      }
    }
  }
  if (needToConvert) {
    print("Converting to RGB space with $needPpi ppi");
    await _optimize(arguments[0], needPpi, force);
  }
  else {
    print("No need to convert - should work intact");
  }

//  final dim1 = pdfData.pages.map((f) => f.dimensions.x).toList();
//  dim1.sort();
//  final scaleX = a2width / dim1.last;
//  final dim2 = pdfData.pages.map((f) => f.dimensions.y).toList();
//  dim1.sort();
//  final scaleY = a2height / dim2.last;
//  final scaleMin = num.parse(min(scaleX, scaleY).toStringAsFixed(2));
//  var tempName = "${arguments[0].substring(0, arguments[0].length-4)}.PROCESSED.pdf";
//  await Process.run('cp', ['${arguments[0]}', '$tempName']);
//  if (scaleMin < 1) {
//    print("Scaling factor: $scaleMin");
//    bool samePages =
//        pdfData.pages.map((f) => f.dimensions.x).toList().reduce(min) == pdfData.pages.first.dimensions.x
//            && pdfData.pages.map((f) => f.dimensions.x).toList().reduce(max) == pdfData.pages.first.dimensions.x
//            && pdfData.pages.map((f) => f.dimensions.y).toList().reduce(min) == pdfData.pages.first.dimensions.y
//            && pdfData.pages.map((f) => f.dimensions.y).toList().reduce(max) == pdfData.pages.first.dimensions.y;
//    if (!samePages) {
//      print("Pages have different sizes, need to separate");
//      await _separatePages(tempName, pdfData.pages.length);
//      await _doResizePages(pdfData, scaleMin);
//      await _concatenate(tempName, pdfData.pages.length);
//    }
//    else {
//      print("Pages have same size, just resizing");
//      await _doResizeFile(tempName, pdfData.pages.first.dimensions, scaleMin);
//    }
//    print("Downsampling images: $tempName");
//    await _downsample(tempName);
//  }
//  else {
//    print("...no need to adjust.");
//  }
}

Future _optimize(String filename, int ppi, bool force) async {
  final args = [
    '-oc',
    '-or',
    '-od',
    '-rc',
    '-ff',
    '-lk',
    '1-RGACU-XVPEE-S8WMX-CNTMD-3WECC-CFJCR-B01LP',
    '-dr',
    '$ppi',
    '-dt',
    '$ppi',
    '-fb',
    '2',
    '-fc',
    '2',
    '-fi',
    '2',
    '-c',
    '1',
    '-ow',
    '$filename',
    '${filename.substring(0, filename.length-4)}.squeezed.pdf'
  ];
  if (force) {
    args.add('-ff');
  }
  await Process.run('./pdfoptimize', args).then((ProcessResult results) {
    final info = results.stdout.toString();
  });
}

Future<PdfData> _getPdfData(String filename) async {
  var pagesCount;
  PdfData pdfData;
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
  await Process.run('pdfimages', ['-list', filename]).then((ProcessResult results) {
    final info = results.stdout.toString().split("\n");
    for (var next in info) {
      final line = next.replaceAll(new RegExp(r"\s+"), " ").toLowerCase();
      final items = line.trim().split(" ");
      try {
        if (items[2] == 'image') {
          final image = new PdfImage(int.parse(items[3]), int.parse(items[4]), int.parse(items[12]), items[5]);
          pdfData.images.add(image);
        }
      }
      catch(ex) {
        //just continue
      }
    }
  });
  return pdfData;
}

class PdfImage {
  final int width;
  final int height;
  final int dpi;
  final String colorSpace;

  int get mpix => width * height;

  PdfImage(this.width, this.height, this.dpi, this.colorSpace);
}

class PdfData {
  final List<PdfPageData> pages = [];
  final List<PdfImage> images = [];
  final bool optimized;
  final int size;

  PdfData(this.optimized, this.size);
}

class PdfPageData {
  final Point dimensions;
  final pageNum;
  PdfPageData(this.pageNum, this.dimensions);
}
