import 'package:logging/logging.dart';

import 'package:mapsforge_flutter/src/mapfileexception.dart';
import '../mapreader/optionalfields.dart';
import '../mapreader/readbuffer.dart';
import '../mapreader/requiredfields.dart';
import 'mapfileinfo.dart';
import 'mapfileinfobuilder.dart';
import 'subfileparameter.dart';
import 'subfileparameterbuilder.dart';

/**
 * Reads and validates the header data from a binary map file.
 */
class MapFileHeader {
  static final _log = new Logger('MapFileHeader');

  /**
   * Maximum valid base zoom level of a sub-file.
   */
  static final int BASE_ZOOM_LEVEL_MAX = 20;

  /**
   * Minimum size of the file header in bytes.
   */
  static final int HEADER_SIZE_MIN = 70;

  /**
   * Length of the debug signature at the beginning of the index.
   */
  static final int SIGNATURE_LENGTH_INDEX = 16;

  /**
   * A single whitespace character.
   */
  static final String SPACE = ' ';

  MapFileInfo mapFileInfo;
  List<SubFileParameter> subFileParameters;
  int zoomLevelMaximum;
  int zoomLevelMinimum;

  /**
   * @return a MapFileInfo containing the header data.
   */
  MapFileInfo getMapFileInfo() {
    return this.mapFileInfo;
  }

  /**
   * @param zoomLevel the originally requested zoom level.
   * @return the closest possible zoom level which is covered by a sub-file.
   */
  int getQueryZoomLevel(int zoomLevel) {
    if (zoomLevel > this.zoomLevelMaximum) {
      return this.zoomLevelMaximum;
    } else if (zoomLevel < this.zoomLevelMinimum) {
      return this.zoomLevelMinimum;
    }
    return zoomLevel;
  }

  /**
   * @param queryZoomLevel the zoom level for which the sub-file parameters are needed.
   * @return the sub-file parameters for the given zoom level.
   */
  SubFileParameter getSubFileParameter(int queryZoomLevel) {
    return this.subFileParameters[queryZoomLevel];
  }

  /**
   * Reads and validates the header block from the map file.
   *
   * @param readBuffer the ReadBuffer for the file data.
   * @param fileSize   the size of the map file in bytes.
   * @throws IOException if an error occurs while reading the file.
   */
  void readHeader(ReadBuffer readBuffer, int fileSize) async {
    await RequiredFields.readMagicByte(readBuffer);
    await RequiredFields.readRemainingHeader(readBuffer);

    MapFileInfoBuilder mapFileInfoBuilder = new MapFileInfoBuilder();

    RequiredFields.readFileVersion(readBuffer, mapFileInfoBuilder);

    RequiredFields.readFileSize(readBuffer, fileSize, mapFileInfoBuilder);

    RequiredFields.readMapDate(readBuffer, mapFileInfoBuilder);

    RequiredFields.readBoundingBox(readBuffer, mapFileInfoBuilder);

    RequiredFields.readTilePixelSize(readBuffer, mapFileInfoBuilder);

    RequiredFields.readProjectionName(readBuffer, mapFileInfoBuilder);

    OptionalFields.readOptionalFieldsStatic(readBuffer, mapFileInfoBuilder);

    RequiredFields.readPoiTags(readBuffer, mapFileInfoBuilder);

    RequiredFields.readWayTags(readBuffer, mapFileInfoBuilder);

    _readSubFileParameters(readBuffer, fileSize, mapFileInfoBuilder);

    this.mapFileInfo = mapFileInfoBuilder.build();
  }

  void debug() {
    _log.info("mapfile is version ${mapFileInfo.fileVersion} from " +
        DateTime.fromMillisecondsSinceEpoch(mapFileInfo.mapDate, isUtc: true)
            .toIso8601String());
    _log.info(mapFileInfo.toString());
    _log.info("zoomLevel: $zoomLevelMinimum - $zoomLevelMaximum");
  }

  void _readSubFileParameters(ReadBuffer readBuffer, int fileSize,
      MapFileInfoBuilder mapFileInfoBuilder) {
    // get and check the number of sub-files (1 byte)
    int numberOfSubFiles = readBuffer.readByte();
    if (numberOfSubFiles < 1) {
      throw new Exception("invalid number of sub-files: $numberOfSubFiles");
    }
    mapFileInfoBuilder.numberOfSubFiles = numberOfSubFiles;

    List<SubFileParameter> tempSubFileParameters = List<SubFileParameter>();
    this.zoomLevelMinimum = 65536;
    this.zoomLevelMaximum = -65536;

    // get and check the information for each sub-file
    for (int currentSubFile = 0;
        currentSubFile < numberOfSubFiles;
        ++currentSubFile) {
      SubFileParameterBuilder subFileParameterBuilder =
          new SubFileParameterBuilder();

      // get and check the base zoom level (1 byte)
      int baseZoomLevel = readBuffer.readByte();
      if (baseZoomLevel < 0 || baseZoomLevel > BASE_ZOOM_LEVEL_MAX) {
        throw new MapFileException("invalid base zoom level: $baseZoomLevel");
      }
      subFileParameterBuilder.baseZoomLevel = baseZoomLevel;

      // get and check the minimum zoom level (1 byte)
      int zoomLevelMin = readBuffer.readByte();
      if (zoomLevelMin < 0 || zoomLevelMin > 22) {
        throw new Exception("invalid minimum zoom level: $zoomLevelMin");
      }
      subFileParameterBuilder.zoomLevelMin = zoomLevelMin;

      // get and check the maximum zoom level (1 byte)
      int zoomLevelMax = readBuffer.readByte();
      if (zoomLevelMax < 0 || zoomLevelMax > 22) {
        throw new Exception("invalid maximum zoom level: $zoomLevelMax");
      }
      subFileParameterBuilder.zoomLevelMax = zoomLevelMax;

      // check for valid zoom level range
      if (zoomLevelMin > zoomLevelMax) {
        throw new Exception(
            "invalid zoom level range: $zoomLevelMin $zoomLevelMax");
      }

      // get and check the start address of the sub-file (8 bytes)
      int startAddress = readBuffer.readLong();
      if (startAddress < HEADER_SIZE_MIN || startAddress >= fileSize) {
        throw new Exception("invalid start address: $startAddress");
      }
      subFileParameterBuilder.startAddress = startAddress;

      int indexStartAddress = startAddress;
      if (mapFileInfoBuilder.optionalFields.isDebugFile) {
        // the sub-file has an index signature before the index
        indexStartAddress += SIGNATURE_LENGTH_INDEX;
      }
      subFileParameterBuilder.indexStartAddress = indexStartAddress;

      // get and check the size of the sub-file (8 bytes)
      int subFileSize = readBuffer.readLong();
      if (subFileSize < 1) {
        throw new Exception("invalid sub-file size: $subFileSize");
      }
      subFileParameterBuilder.subFileSize = subFileSize;

      subFileParameterBuilder.boundingBox = mapFileInfoBuilder.boundingBox;

      // add the current sub-file to the list of sub-files
      SubFileParameter subFileParameter = subFileParameterBuilder.build();
      tempSubFileParameters.add(subFileParameter);

      // update the global minimum and maximum zoom level information
      if (this.zoomLevelMinimum > subFileParameter.zoomLevelMin) {
        this.zoomLevelMinimum = subFileParameter.zoomLevelMin;
        mapFileInfoBuilder.zoomLevelMin = this.zoomLevelMinimum;
      }
      if (this.zoomLevelMaximum < subFileParameter.zoomLevelMax) {
        this.zoomLevelMaximum = subFileParameter.zoomLevelMax;
        mapFileInfoBuilder.zoomLevelMax = this.zoomLevelMaximum;
      }
    }

    // create and fill the lookup table for the sub-files
    this.subFileParameters =
        new List<SubFileParameter>(this.zoomLevelMaximum + 1);
    for (int currentMapFile = 0;
        currentMapFile < numberOfSubFiles;
        ++currentMapFile) {
      SubFileParameter subFileParameter =
          tempSubFileParameters.elementAt(currentMapFile);
      for (int zoomLevel = subFileParameter.zoomLevelMin;
          zoomLevel <= subFileParameter.zoomLevelMax;
          ++zoomLevel) {
        this.subFileParameters[zoomLevel] = subFileParameter;
      }
    }
  }
}
