import Flutter
import AVFoundation

public class VideoCompressPlugin: NSObject, FlutterPlugin {
    private let channelName = "video_compress"
    private var exporter: AVAssetExportSession? = nil
    private var stopCommand = false
    private let channel: FlutterMethodChannel
    private let avController = AvController()
    private var assetReader: AVAssetReader?
    private var assetWriter: AVAssetWriter?
    private var isCompressing = false
    
    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "video_compress", binaryMessenger: registrar.messenger())
        let instance = VideoCompressPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? Dictionary<String, Any>
        switch call.method {
        case "getByteThumbnail":
            let path = args!["path"] as! String
            let quality = args!["quality"] as! NSNumber
            let position = args!["position"] as! NSNumber
            getByteThumbnail(path, quality, position, result)
        case "getFileThumbnail":
            let path = args!["path"] as! String
            let quality = args!["quality"] as! NSNumber
            let position = args!["position"] as! NSNumber
            getFileThumbnail(path, quality, position, result)
        case "getMediaInfo":
            let path = args!["path"] as! String
            getMediaInfo(path, result)
        case "compressVideo":
            let path = args!["path"] as! String
            let output = args!["output"] as! String
            var quality = 5
            if (args!["quality"] != nil) {
                quality = args!["quality"] as! Int
            }
            let deleteOrigin = args!["deleteOrigin"] as! Bool
            let startTime = args!["startTime"] as? Double
            let duration = args!["duration"] as? Double
            let includeAudio = args!["includeAudio"] as? Bool
            let frameRate = args!["frameRate"] as? Int
            compressVideo(path, output, quality, deleteOrigin, startTime, duration, includeAudio, frameRate, result)
        case "cancelCompression":
            cancelCompression(result)
        case "deleteAllCache":
            Utility.deleteFile(Utility.basePath(), clear: true)
            result(true)
        case "setLogLevel":
            result(true)
        case "compressVideoIOS":

            let inputPath = args!["inputFile"] as! String
            let outputPath = args!["outputFile"] as! String
            let inputURL = URL(fileURLWithPath: inputPath)
            let outputURL = URL(fileURLWithPath: outputPath)

            let width = args!["width"] as! Double
            let height = args!["height"] as! Double
            let size = CGSize(width: width, height: height)

            let frameRate = args!["frameRate"] as! Int32
            let bitrate = args!["bitrate"] as! Int?

            do {
                try startCompression(inputURL: inputURL,outputURL: outputURL, videoSize: size, frameRate: frameRate, bitrate: bitrate) { (compressedURL, error) in if let compressedURL = compressedURL {
                    print("Compressed video saved to: \(compressedURL)")
                    result(compressedURL.path)
                } else if let error = error {
                    print("Compression failed with error: \(error.localizedDescription)")
                    result(nil)
                }
                else {
                    result(nil)
                }
                }
            }
            catch {
                result(nil)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func getBitMap(_ path: String,_ quality: NSNumber,_ position: NSNumber,_ result: FlutterResult)-> Data?  {
        let url = Utility.getPathUrl(path)
        let asset = avController.getVideoAsset(url)
        guard let track = avController.getTrack(asset) else { return nil }
        
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        
        let timeScale = CMTimeScale(track.nominalFrameRate)
        let time = CMTimeMakeWithSeconds(Float64(truncating: position),preferredTimescale: timeScale)
        guard let img = try? assetImgGenerate.copyCGImage(at:time, actualTime: nil) else {
            return nil
        }
        let thumbnail = UIImage(cgImage: img)
        let compressionQuality = CGFloat(0.01 * Double(truncating: quality))
        return thumbnail.jpegData(compressionQuality: compressionQuality)
    }
    
    private func getByteThumbnail(_ path: String,_ quality: NSNumber,_ position: NSNumber,_ result: FlutterResult) {
        if let bitmap = getBitMap(path,quality,position,result) {
            result(bitmap)
        }
    }
    
    private func getFileThumbnail(_ path: String,_ quality: NSNumber,_ position: NSNumber,_ result: FlutterResult) {
        let fileName = Utility.getFileName(path)
        let url = Utility.getPathUrl("\(Utility.basePath())/\(fileName).jpg")
        Utility.deleteFile(path)
        if let bitmap = getBitMap(path,quality,position,result) {
            guard (try? bitmap.write(to: url)) != nil else {
                return result(FlutterError(code: channelName,message: "getFileThumbnail error",details: "getFileThumbnail error"))
            }
            result(Utility.excludeFileProtocol(url.absoluteString))
        }
    }
    
    public func getMediaInfoJson(_ path: String)->[String : Any?] {
        let url = Utility.getPathUrl(path)
        let asset = avController.getVideoAsset(url)
        guard let track = avController.getTrack(asset) else { return [:] }
        
        let playerItem = AVPlayerItem(url: url)
        let metadataAsset = playerItem.asset
        
        let orientation = avController.getVideoOrientation(path)
        
        let title = avController.getMetaDataByTag(metadataAsset,key: "title")
        let author = avController.getMetaDataByTag(metadataAsset,key: "author")
        
        let duration = asset.duration.seconds * 1000
        let fileSize = track.totalSampleDataLength
        
        let size = track.naturalSize.applying(track.preferredTransform)
        
        let width = Int(abs(size.width))
        let height = Int(abs(size.height))
        
        let dictionary = [
            "path":Utility.excludeFileProtocol(path),
            "title":title,
            "author":author,
            "width":width,
            "height":height,
            "duration":duration,
            "fileSize":fileSize,
            "orientation":orientation
            ] as [String : Any?]
        return dictionary
    }
    
    private func getMediaInfo(_ path: String,_ result: FlutterResult) {
        let json = getMediaInfoJson(path)
        let string = Utility.keyValueToJson(json)
        result(string)
    }
    
    
    @objc private func updateProgress(timer:Timer) {
        let asset = timer.userInfo as! AVAssetExportSession
        if(!stopCommand) {
            channel.invokeMethod("updateProgress", arguments: "\(String(describing: asset.progress * 100))")
        }
    }
    
    private func getExportPreset(_ quality: Int)->String {
        switch(quality) {
        case 1:
            return AVAssetExportPresetLowQuality    
        case 2:
            return AVAssetExportPresetMediumQuality
        case 3:
            return AVAssetExportPresetHighestQuality
        case 4:
            return AVAssetExportPreset640x480
        case 5:
            return AVAssetExportPreset960x540
        case 6:
            return AVAssetExportPreset1280x720
        case 7:
            return AVAssetExportPreset1920x1080
        default:
            return AVAssetExportPresetMediumQuality
        }
    }
    
    private func getComposition(_ isIncludeAudio: Bool,_ timeRange: CMTimeRange, _ sourceVideoTrack: AVAssetTrack)->AVAsset {
        let composition = AVMutableComposition()
        if !isIncludeAudio {
            let compressionVideoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
            compressionVideoTrack!.preferredTransform = sourceVideoTrack.preferredTransform
            try? compressionVideoTrack!.insertTimeRange(timeRange, of: sourceVideoTrack, at: CMTime.zero)
        } else {
            return sourceVideoTrack.asset!
        }
        
        return composition    
    }
    
    private func compressVideo(_ path: String,_ output: String, _ quality: Int,_ deleteOrigin: Bool,_ startTime: Double?,
                               _ duration: Double?,_ includeAudio: Bool?,_ frameRate: Int?,
                               _ result: @escaping FlutterResult) {
        let sourceVideoUrl = Utility.getPathUrl(path)
        let sourceVideoType = "mp4"
        
        let sourceVideoAsset = avController.getVideoAsset(sourceVideoUrl)
        let sourceVideoTrack = avController.getTrack(sourceVideoAsset)
        
        let compressionUrl = Utility.getPathUrl(output) //Utility.getPathUrl("\(Utility.basePath())/\(Utility.getFileName(path)).\(sourceVideoType)")
        
        let timescale = sourceVideoAsset.duration.timescale
        let minStartTime = Double(startTime ?? 0)
        
        let videoDuration = sourceVideoAsset.duration.seconds
        let minDuration = Double(duration ?? videoDuration)
        let maxDurationTime = minStartTime + minDuration < videoDuration ? minDuration : videoDuration
        
        let cmStartTime = CMTimeMakeWithSeconds(minStartTime, preferredTimescale: timescale)
        let cmDurationTime = CMTimeMakeWithSeconds(maxDurationTime, preferredTimescale: timescale)
        let timeRange: CMTimeRange = CMTimeRangeMake(start: cmStartTime, duration: cmDurationTime)
        
        let isIncludeAudio = includeAudio != nil ? includeAudio! : true
        
        if (sourceVideoTrack != nil) {
            let session = getComposition(isIncludeAudio, timeRange, sourceVideoTrack!)

            let exporter = AVAssetExportSession(asset: session, presetName: getExportPreset(quality))!
            
            exporter.outputURL = compressionUrl
            exporter.outputFileType = AVFileType.mp4
            exporter.shouldOptimizeForNetworkUse = true
            
            if frameRate != nil {
                let videoComposition = AVMutableVideoComposition(propertiesOf: sourceVideoAsset)
                videoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate!))
                exporter.videoComposition = videoComposition
            }
            
            if !isIncludeAudio {
                exporter.timeRange = timeRange
            }
            
            Utility.deleteFile(compressionUrl.absoluteString)
            
            let timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.updateProgress),
                                             userInfo: exporter, repeats: true)
            
            exporter.exportAsynchronously(completionHandler: {
                timer.invalidate()
                if(self.stopCommand) {
                    self.stopCommand = false
                    var json = self.getMediaInfoJson(path)
                    json["isCancel"] = true
                    let jsonString = Utility.keyValueToJson(json)
                    return result(jsonString)
                }
                if deleteOrigin {
                    let fileManager = FileManager.default
                    do {
                        if fileManager.fileExists(atPath: path) {
                            try fileManager.removeItem(atPath: path)
                        }
                        self.exporter = nil
                        self.stopCommand = false
                    }
                    catch let error as NSError {
                        print(error)
                    }
                }
                var json = self.getMediaInfoJson(Utility.excludeEncoding(compressionUrl.path))
                json["isCancel"] = false
                let jsonString = Utility.keyValueToJson(json)
                result(jsonString)
            })
        }
        else {
            result("")
        }
    }
    
    private func cancelCompression(_ result: FlutterResult) {
        exporter?.cancelExport()
        stopCommand = true
        result("")
    }



    // ------------------------------------------------------------------
        // AVAssetWriter re-encoding
        // ------------------------------------------------------------------

        func startCompression(inputURL: URL,outputURL: URL, videoSize: CGSize, frameRate: Int32, bitrate: Int?,completion: @escaping (URL?, Error?) -> Void) throws {
             if(isCompressing) {
             completion(nil,nil)
             print("cannot compress multiple file at the same time")
                return
             }
             isCompressing = true
            //video file to make the asset

            var audioFinished = false
            var videoFinished = false

            let asset = AVAsset(url: inputURL);

            //create asset reader
            do{
                assetReader = try AVAssetReader(asset: asset)
            } catch{
                assetReader = nil
            }

            if(assetReader == nil) {
                completion(nil,nil)
                fatalError("asset reader is nil")
                return;
            }

            let videoTrack = asset.tracks(withMediaType: AVMediaType.video).first!
            let audioTrack = asset.tracks(withMediaType: AVMediaType.audio).first

            let videoFormatDescription = videoTrack.formatDescriptions.first as! CMFormatDescription
            let audioFormatDescription = audioTrack != nil ? audioTrack!.formatDescriptions.first as! CMFormatDescription : nil


                    // HANDLE ROTATIONS
            let txf = videoTrack.preferredTransform
            let bit = videoTrack.estimatedDataRate
            print("initial bitrate ",bit)
            print("optmized bitrate ",bit/2)

            print("video transform : ",txf)
            // Get the natural size of the video track
            let size = videoTrack.naturalSize

            print("natural size width ",size.width)
            print("natural size height ",size.height)
            var preferredTransform = videoTrack.preferredTransform
            var videoRotateSize = videoSize
            var rotation = preferredTransform

            // Check the transform's rotation type
            if preferredTransform.a == 0 && preferredTransform.d == 0 {
                // 90 or -90 degree rotation (portrait/landscape switch)
                // Swap the width and height for these cases.
                videoRotateSize = CGSize(width: videoSize.height, height: videoSize.width)
            } else if preferredTransform.a == 1 && preferredTransform.d == 1 {
                // No rotation (no transform applied)
                rotation = CGAffineTransform.identity
            } else {
                // Other transforms (like 180-degree rotations, flips, etc.)
                // Keep the natural size as is.
                // You could handle additional flips, but for the most common cases, this suffices.
                rotation = preferredTransform
            }

            // The compressed general value
            var finalBitRate = 2500000

            if(bitrate != nil) {
                finalBitRate = bitrate!
            }
            // If the origin is lower than the final bitrate this is because original video is already very
            // compressed
            // So we / 2 the original video bitrate
            if(finalBitRate > Int(bit/2)) {
                finalBitRate = Int(bit/2)
            }

            print("final bite rate : ",finalBitRate)

            // Define custom compression settings.
            let compressionSettings: [String: Any] = [
                AVVideoAverageBitRateKey: finalBitRate,              // Target bitrate (e.g., 500_000 for 500 kbps or 1_000_000 for 1000 kbps).
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, // H.264 Profile Level.
                AVVideoMaxKeyFrameIntervalKey: frameRate,              // Maximum key frame interval (1 key frame every 30 frames).
                AVVideoAllowFrameReorderingKey: true,           // Allow frame reordering for better compression.
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC // Better compression than CAVLC.
            ]

            // Define video output settings.
            let videoOutputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoRotateSize.width,
                AVVideoHeightKey: videoRotateSize.height,
                AVVideoCompressionPropertiesKey: compressionSettings
            ]

            let audioOutputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVEncoderBitRateKey: 128_000,                    // Target bitrate (e.g., 64 kbps for speech).
                AVNumberOfChannelsKey: 2,                       // Stereo audio.
                AVSampleRateKey: 44_100, // Standard audio sample rate.
                AVEncoderAudioQualityKey: AVAudioQuality.medium,
            ]

            let videoReaderSettings: [String:Any] =  [(kCVPixelBufferPixelFormatTypeKey as String?)!:kCVPixelFormatType_32ARGB ]

    //                    let audioReaderSettings: [String: Any] = [
    //                        AVFormatIDKey: kAudioFormatLinearPCM,
    //                        AVSampleRateKey: 44100,
    //                        AVNumberOfChannelsKey: 2,
    //                        AVLinearPCMBitDepthKey: 16,
    //                        AVLinearPCMIsFloatKey: false,
    //                        AVLinearPCMIsBigEndianKey: false,
    //                    ]

            let assetReaderVideoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
            let assetReaderAudioOutput = audioTrack != nil ? AVAssetReaderTrackOutput(track: audioTrack!,outputSettings: nil) : nil


            if assetReader!.canAdd(assetReaderVideoOutput){
                assetReader!.add(assetReaderVideoOutput)
            }else{
                completion(nil,nil)
                fatalError("Couldn't add video output reader")
            }

            if(assetReaderAudioOutput != nil) {
                if assetReader!.canAdd(assetReaderAudioOutput!){
                    assetReader!.add(assetReaderAudioOutput!)
                }else{
                    completion(nil,nil)
                    fatalError("Couldn't add audio output reader")
                }
            }

            let audioInput = audioTrack != nil ? AVAssetWriterInput(mediaType: .audio, outputSettings: nil,sourceFormatHint: audioFormatDescription) : nil
            if(audioInput != nil) {
                audioInput!.expectsMediaDataInRealTime = true
            }


            let videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoOutputSettings,sourceFormatHint: videoFormatDescription)

            videoInput.transform = rotation
            //we need to add samples to the video input

            videoInput.expectsMediaDataInRealTime = true  // Needed for real-time encoding.


            let videoInputQueue = DispatchQueue(label: "videoQueue")
            let audioInputQueue = DispatchQueue(label: "audioQueue")

            do{
                self.assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4)
            }catch{
                self.assetWriter = nil
            }
            if(assetWriter == nil) {
                completion(nil,nil)
                fatalError("Asset writer is nil")
                return
            }

            assetWriter!.shouldOptimizeForNetworkUse = true
            assetWriter!.add(videoInput)
            if(audioInput != nil) {
                assetWriter!.add(audioInput!)
            }
            else {
                audioFinished = true
            }

            assetWriter!.startWriting()
            assetReader!.startReading()

            assetWriter!.startSession(atSourceTime: CMTime.zero)


            let closeWriter:()->Void = {
                if (videoFinished && audioFinished) {
                    self.assetWriter?.finishWriting(completionHandler: {
                        completion((self.assetWriter?.outputURL)!,nil)
                    })
                    self.assetReader?.cancelReading()
                    self.isCompressing = false
                }
            }
            
            
            if(audioInput != nil && assetReaderAudioOutput != nil) {
                
                audioInput!.requestMediaDataWhenReady(on: audioInputQueue) {
                    while(audioInput!.isReadyForMoreMediaData){
                        let sample = assetReaderAudioOutput!.copyNextSampleBuffer()
                        if (sample != nil){
                            audioInput!.append(sample!)
                        }else{
                            audioInput!.markAsFinished()
                            DispatchQueue.main.async {
                                audioFinished = true
                                closeWriter()
                            }
                            break;
                        }
                    }
                }
            }

            videoInput.requestMediaDataWhenReady(on: videoInputQueue) {
                //request data here
                while(videoInput.isReadyForMoreMediaData){
                    let sample = assetReaderVideoOutput.copyNextSampleBuffer()
                    if (sample != nil){
                        videoInput.append(sample!)
                    }else{
                        videoInput.markAsFinished()
                        DispatchQueue.main.async {
                            videoFinished = true
                            closeWriter()
                        }
                        break;
                    }
                }
            }

        }
    
}
