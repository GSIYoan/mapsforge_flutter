import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:logging/logging.dart';
import 'package:mapsforge_flutter/src/graphics/tilebitmap.dart';
import 'package:mapsforge_flutter/src/implementation/graphics/fluttertilebitmap.dart';
import 'package:mapsforge_flutter/src/model/tile.dart';
import 'package:mapsforge_flutter/src/utils/filehelper.dart';

import 'bitmapcache.dart';
import 'memorybitmapcache.dart';

class FileBitmapCache extends BitmapCache {
  static final _log = new Logger('FileBitmapCache');

  final MemoryBitmapCache _memoryBitmapCache;

  String renderkey;

  List<String> files;

  String dir;

  FileBitmapCache(this.renderkey) : _memoryBitmapCache = MemoryBitmapCache() {
    _init();
  }

  Future _init() async {
    assert(renderkey != null && !renderkey.contains("/"));
    dir = await FileHelper.getTempDirectory("mapsforgetiles/" + renderkey);
    files = await FileHelper.getFiles(dir);
    _log.info("Starting cache for renderkey $renderkey with ${files.length} items in filecache");
//    files.forEach((file) {
//      _log.info("  file in cache: $file");
//    });
  }

  void purge() async {
    if (files == null) return;
    int count = 0;
    await files.forEach((file) async {
      _log.info("  purging file from cache: $file");
      bool ok = await FileHelper.delete(file);
      if (ok) ++count;
    });
    _log.info("purged $count files from cache $renderkey");
    files.clear();
  }

  @override
  void addTileBitmap(Tile tile, TileBitmap tileBitmap) {
    _memoryBitmapCache.addTileBitmap(tile, tileBitmap);
    _storeFile(tile, tileBitmap);
  }

  @override
  TileBitmap getTileBitmap(Tile tile) {
    TileBitmap tileBitmap = _memoryBitmapCache.getTileBitmap(tile);
    return tileBitmap;
  }

  @override
  Future<TileBitmap> getTileBitmapAsync(Tile tile) async {
    TileBitmap tileBitmap = _memoryBitmapCache.getTileBitmap(tile);
    if (tileBitmap != null) return tileBitmap;

    String filename = _calculateFilename(tile);
    if (files == null || !files.contains(filename)) {
      // not yet initialized or not in cache
      return null;
    }
    File file = File(filename);
    Uint8List content = await file.readAsBytes();
    var codec = await instantiateImageCodec(content.buffer.asUint8List());
    // add additional checking for number of frames etc here
    var frame = await codec.getNextFrame();
    Image img = frame.image;
    tileBitmap = FlutterTileBitmap(img);
    _memoryBitmapCache.addTileBitmap(tile, tileBitmap);
    return tileBitmap;
  }

  Future _storeFile(Tile tile, TileBitmap tileBitmap) async {
    String filename = _calculateFilename(tile);
    if (files == null) {
      // not yet initialized
      return;
    }
    if (files.contains(filename)) return;
    Image img = (tileBitmap as FlutterTileBitmap).bitmap;
    ByteData content = await img.toByteData(format: ImageByteFormat.png);
    File file = File(filename);
    file.writeAsBytes(content.buffer.asUint8List(), mode: FileMode.write);
    files.add(filename);
  }

  String _calculateFilename(Tile tile) {
    return "$dir/${tile.zoomLevel}_${tile.tileX}_${tile.tileY}.png";
  }

  @override
  void dispose() {
    _memoryBitmapCache.dispose();
  }
}
