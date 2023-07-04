// ignore_for_file: avoid_print, depend_on_referenced_packages, unused_import

import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

class PhotoPicker extends StatefulWidget {
  final List<String> images;
  final ValueChanged<List<String>> onImagesChanged;
  final int maxImages;
  final bool confirmDelete;
  final int maxPx;
  final int imgQuality;

  const PhotoPicker(
      {super.key,
      required this.images,
      required this.onImagesChanged,
      this.maxImages = 5,
      this.confirmDelete = true,
      this.maxPx = 1000,
      this.imgQuality = 75});

  @override
  State<PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends State<PhotoPicker> {
  final Uuid uuid = const Uuid();
  final String account = 'flutterstorageaus';
  final String container = 'main';
  final String sasKey =
      '?sv=2022-11-02&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2023-07-31T13:16:53Z&st=2023-06-02T05:16:53Z&spr=https,http&sig=djHBgAyoXw5CumOfRZovvnFdlce0jIZ1FbDmh%2B9OYW8%3D';
  final List<CustomAsset> _images = [];

  @override
  void initState() {
    super.initState();
    _retrieveFromAzure(widget.images);
  }

  Future<void> _pickImage() async {
    var assets = await AssetPicker.pickAssets(context,
        pickerConfig:
            AssetPickerConfig(maxAssets: widget.maxImages - _images.length));

    if (assets != null) {
      setState(() {
        for (var i = 0; i < assets.length; i++) {
          var customAsset = CustomAsset(id: uuid.v4(), assetEntity: assets[i]);
          _images.add(customAsset);
          _uploadToAzure(customAsset);
        }
      });
    }
  }

  Future<void> _takeImage() async {
    if (_images.length > 5) {
      return;
    }

    var asset = await CameraPicker.pickFromCamera(context);
    if (asset != null) {
      var customAsset = CustomAsset(id: uuid.v4(), assetEntity: asset);
      setState(() {
        _images.add(customAsset);
        _uploadToAzure(customAsset);
      });
    }
  }

  void _deleteImage(CustomAsset customAsset) {
    setState(() {
      _images.remove(customAsset);
      _removeFromAzure(customAsset);
    });
  }

  void _confirmDelete(CustomAsset customAsset) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm'),
          content: const Text('Are you sure you want to delete this image?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Yes, delete'),
              onPressed: () {
                _deleteImage(customAsset);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _retrieveFromAzure(List<String> images) async {
    for (var fileName in images) {
      var url =
          'https://$account.blob.core.windows.net/$container/$fileName$sasKey';
      var request = http.Request("GET", Uri.parse(url));

      try {
        var response = await request.send();
        if (response.statusCode == 200) {
          var id = p.basenameWithoutExtension(fileName);
          var blobData = await response.stream.toBytes();
          var assetEntity =
              await PhotoManager.editor.saveImage(blobData, title: id);

          if (assetEntity == null) {
            throw ("Asset entity was null...");
          }

          var customAsset = CustomAsset(id: id, assetEntity: assetEntity);
          setState(() {
            _images.add(customAsset);
          });
        } else {
          throw ("Retrieval failed with status: ${response.statusCode}.");
        }
      } catch (e) {
        print("Exception caught: $e");
      }
    }
  }

  Future<void> _uploadToAzure(CustomAsset customAsset) async {
    var fileName = await customAsset.getFileName();
    var url =
        'https://$account.blob.core.windows.net/$container/$fileName$sasKey';
    var request = http.Request("PUT", Uri.parse(url));

    request.headers['x-ms-blob-type'] = "BlockBlob";

    try {
      var file = await customAsset.assetEntity.file;
      if (file != null) {
        var image = img.decodeImage(await file.readAsBytes());
        if (image != null) {
          var resizedImage = img.copyResize(image, width: widget.maxPx);
          var jpg = img.encodeJpg(resizedImage, quality: widget.imgQuality);

          request.bodyBytes = jpg;
          var response = await request.send();

          if (response.statusCode == 201) {
            print("Uploaded!");

            var thumbFileName = 'thumb_$fileName';
            var thumbUrl =
                'https://$account.blob.core.windows.net/$container/$thumbFileName$sasKey';
            var thumbRequest = http.Request("PUT", Uri.parse(thumbUrl));
            thumbRequest.headers['x-ms-blob-type'] = "BlockBlob";

            var thumbnail = img.copyResize(image, width: 100);
            var png = img.encodePng(thumbnail);
            thumbRequest.bodyBytes = png;
            var thumbResponse = await thumbRequest.send();

            if (thumbResponse.statusCode == 201) {
              print("Thumbnail uploaded!");
            } else {
              throw ("Thumbnail upload failed with status: ${thumbResponse.statusCode}.");
            }
          } else {
            throw ("Upload failed with status: ${response.statusCode}.");
          }
        } else {
          throw ("Failed to retrieve byte data from asset entity.");
        }
      }

      var imageNames = await _getImageNamesList();
      widget.onImagesChanged(imageNames);
    } catch (e) {
      setState(() {
        _images.remove(customAsset);
      });
      print("Exception caught: $e");
    }
  }

  Future<void> _removeFromAzure(CustomAsset customAsset) async {
    var fileName = await customAsset.getFileName();
    var url =
        'https://$account.blob.core.windows.net/$container/$fileName$sasKey';

    var request = http.Request("DELETE", Uri.parse(url));

    try {
      var response = await request.send();

      if (response.statusCode == 202) {
        print("Removed!");

        var thumbFileName = 'thumb_$fileName';
        var thumbUrl =
            'https://$account.blob.core.windows.net/$container/$thumbFileName$sasKey';
        var thumbRequest = http.Request("DELETE", Uri.parse(thumbUrl));
        var thumbResponse = await thumbRequest.send();

        if (thumbResponse.statusCode == 202) {
          print("Thumbnail removed!");
        } else {
          throw ("Thumbnail removal failed with status: ${thumbResponse.statusCode}.");
        }
      } else {
        throw ("Removal failed with status: ${response.statusCode}.");
      }

      var imageNames = await _getImageNamesList();
      widget.onImagesChanged(imageNames);
    } catch (e) {
      setState(() {
        _images.add(customAsset);
      });
      print("Exception caught: $e");
    }
  }

  Future<List<String>> _getImageNamesList() async {
    List<String> imageNames = [];

    for (var image in _images) {
      imageNames.add(await image.getFileName());
    }

    return imageNames;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<int>(
            child: const Icon(Icons.camera_alt, color: Colors.deepOrange),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 1,
                child: Text("Pick image(s) from library"),
              ),
              const PopupMenuItem(
                value: 2,
                child: Text("Take a picture"),
              ),
            ],
            onSelected: (value) {
              if (value == 1) {
                _pickImage();
              } else if (value == 2) {
                _takeImage();
              }
            },
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length,
            itemBuilder: (context, index) {
              var customAsset = _images[index];
              return Padding(
                padding: const EdgeInsets.all(5),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.center,
                      child: AssetEntityImage(
                        customAsset.assetEntity,
                        width: 100.0,
                        height: 100.0,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon:
                            const Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () {
                          if (widget.confirmDelete) {
                            _confirmDelete(customAsset);
                          } else {
                            _deleteImage(customAsset);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CustomAsset {
  String id;
  AssetEntity assetEntity;

  Future<String> getFileName() async {
    var file = await assetEntity.file;
    if (file == null) {
      return "";
    }

    String extension = p.extension(file.path);
    String fileName = id + extension;

    return fileName;
  }

  CustomAsset({required this.id, required this.assetEntity});
}
