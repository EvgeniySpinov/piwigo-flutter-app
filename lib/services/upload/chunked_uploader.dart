import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_uploader/flutter_uploader.dart';

class ChunkedUploader {
  final Dio _dio;

  ChunkedUploader(this._dio);

  Future<Response> upload({
    String filePath,
    String path,
    String contentType,
    Map<String, dynamic> data,
    Map<String, String> params,
    CancelToken cancelToken,
    int maxChunkSize,
    Function(double) onUploadProgress,
    String method = 'POST',
    String fileKey = 'file',
  }) =>
      UploadRequest(_dio,
              filePath: filePath,
              path: path,
              contentType: contentType,
              params: params,
              fileKey: fileKey,
              method: method,
              data: data,
              cancelToken: cancelToken,
              maxChunkSize: maxChunkSize,
              onUploadProgress: onUploadProgress)
          .upload();
}

class UploadRequest {
  final Dio dio;
  final uploader = FlutterUploader();
  final String filePath, fileName, path,fileKey;
  final Map<String, String> params;
  final String method;
  final String contentType;
  final Map<String, dynamic> data;
  final CancelToken cancelToken;
  final File _file;
  final Function(double) onUploadProgress;
  int _maxChunkSize,_fileSize;

  UploadRequest(this.dio,
      {this.filePath,
      this.params,
      this.contentType,
      this.path,
      this.fileKey,
      this.method,
      this.data,
      this.cancelToken,
      this.onUploadProgress,
      int maxChunkSize})
      : _file = File(filePath),
        fileName = p.basename(filePath) {
    _fileSize = _file.lengthSync();
    _maxChunkSize = min(_fileSize, maxChunkSize ?? _fileSize);
  }

  Future<Response> upload() async {
    Future<Response> finalResponse;
    String originalSum;
    List<String> chunkSums = [];
    originalSum = (await crypto.md5.bind(_file.openRead()).first).toString();
    for (int i = 0; i < _chunksCount; i++) {
      final start = _getChunkStart(i);
      final end = _getChunkEnd(i);
      final chunkStream = _getChunkStream(start, end);
      chunkSums.add((await crypto.md5.bind(chunkStream).first).toString());
    }

    for (int i = 0; i < _chunksCount; i++) {
      print("${i+1} | $_chunksCount");
      final start = _getChunkStart(i);
      final end = _getChunkEnd(i);
      final chunkStream = _getChunkStream(start, end);

      final formData = FormData.fromMap({
        "chunks": _chunksCount,
        "chunk": i,
        "chunk_sum": chunkSums[i],
        "original_sum": originalSum,
        "file": MultipartFile(chunkStream, end - start, filename: fileName),
        if (data != null) ...data
      });
      try {
        finalResponse = dio.request(
          path,
          data: formData,
          // cancelToken: cancelToken,
          queryParameters: params,
          options: Options(
              method: method,
              // headers: _getHeaders(start, end),
              contentType: contentType
          ),
          onSendProgress: (current, total) => _updateProgress(i, current, total),
        );
      } catch (e) {
        print(e);
      }
    }
    return finalResponse;
  }

  Stream<List<int>> _getChunkStream(int start, int end) =>
      _file.openRead(start, end);

  // Updating total upload progress
  _updateProgress(int chunkIndex, int chunkCurrent, int chunkTotal) {
    int totalUploadedSize = (chunkIndex * _maxChunkSize) + chunkCurrent;
    double totalUploadProgress = totalUploadedSize / _fileSize;
    this.onUploadProgress?.call(totalUploadProgress);
  }

  // Returning start byte offset of current chunk
  int _getChunkStart(int chunkIndex) => chunkIndex * _maxChunkSize;

  // Returning end byte offset of current chunk
  int _getChunkEnd(int chunkIndex) =>
      min((chunkIndex + 1) * _maxChunkSize, _fileSize);

  // Returning a header map object containing Content-Range
  // https://tools.ietf.org/html/rfc7233#section-2
  Map<String, dynamic> _getHeaders(int start, int end) =>
      {'Content-Range': 'bytes $start-${end - 1}/$_fileSize'};

  // Returning chunks count based on file size and maximum chunk size
  int get _chunksCount => (_fileSize / _maxChunkSize).ceil();


  Future<String> generateMd5(Stream stream) async {
    return (await crypto.md5.bind(stream).first).toString();
  }
}
