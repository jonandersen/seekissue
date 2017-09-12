import Foundation
import AVFoundation
import RxSwift
import MobileCoreServices


public enum ResultProgress<T> {
    case result(T)
    case progress(Double, Int, Int)
    
    func isProgress() -> Bool {
        switch self {
        case .result(_) : return false
        case .progress(_) : return true
            
        }
    }
    
    func map<U>(_ mappingFn: (T) -> U) -> ResultProgress<U>{
        switch self {
        case .progress(let progress, let start, let end): return .progress(progress, start, end)
        case .result(let result): return .result(mappingFn(result))
        }
    }
}


class ExportManager {
    
    public init() {
        
    }

    
    func cleanUp() {
        deleteFile("LeapSecond.mp4")
    }
    
    
    func exportCompostion(_ exportComposition: MutableExportComposition) -> Observable<ResultProgress<URL>>  {
        print("Exporting")
        do {
            let file = try createFile("LeapSecond.mp4")
            let encoder = try exportComposition.toSession(file)
            return self.export(encoder)
        } catch let error as NSError {
            return Observable.error(error)
        }
    }
    
    
    //MARK - Private
 

    private func export(_ session: AVAssetExportSession) -> Observable<ResultProgress<URL>> {
        return Observable.create{ subscriber in
            subscriber.onNext(.progress(0.0, 1, 1))
            
            session.exportAsynchronously {() -> Void in
                print("Export Session - Completed")
                switch session.status {
                case  .failed:
                    subscriber.onError(session.error!)
                case .cancelled:
                    subscriber.onError(session.error!)
                case .exporting: break
                case .completed:
                    subscriber.onNext(.progress(1.0, 1, 1))
                    if let url = session.outputURL {
                        subscriber.onNext(.result(url))
                        subscriber.onCompleted()
                    }else{
                        subscriber.onError(session.error!)
                    }
                default:
                    subscriber.onError(session.error!)
                }
            }
            return Disposables.create {
                session.cancelExport()
            }
        }
    }
}



class MutableExportComposition {
    private let mixComposition: AVMutableComposition = AVMutableComposition()
    private let videoTrack: AVMutableCompositionTrack
    private let audioTrack: AVMutableCompositionTrack
    private var insertTime: CMTime = kCMTimeZero
    private let size: CGSize
    private var instructions: [AVMutableVideoCompositionInstruction] = []
    private var addedAudio = false
    
    public init () {
        size = CGSize(width: 1280, height: 720)
        videoTrack  = mixComposition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
        audioTrack = mixComposition.addMutableTrack(withMediaType: AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)
    }
    
    func getComposition() -> AVComposition {
        return mixComposition
    }
    
    func insertAssets(_ assets: [AVAsset])  {
        assets.forEach(self.insertAsset)
    }
    
    private func insertAsset(_ asset: AVAsset) -> () {
        let videoTracks = asset.tracks(withMediaType: AVMediaTypeVideo)
        let audioTracks = asset.tracks(withMediaType: AVMediaTypeAudio)
        
        //TODO remove timescale
        guard let vTrack = videoTracks.first, vTrack.naturalTimeScale == 600, vTrack.timeRange.duration.seconds == 1.0 else {
            return
        }
        
        
        let videoTrackDuration = vTrack.timeRange.duration //.convertScale(Int32(NSEC_PER_SEC), method: .roundTowardZero)
        //        let videoTrackDuration = CMTimeSubtract(vTrack.timeRange.duration, CMTimeMake(20, 600))
        //        let videoTrackDuration = CMTimeMakeWithSeconds(CMTimeGetSeconds(vTrack.timeRange.duration), Int32(NSEC_PER_SEC))
        
        //        let videoTrackRange = vTrack.timeRange
        let videoTrackRange = CMTimeRangeMake(vTrack.timeRange.start, videoTrackDuration)
        
        print("range: \(vTrack.naturalTimeScale) - \(videoTrackDuration.seconds) - \(videoTrackDuration)")
        
        if vTrack.timeRange.start > kCMTimeZero {
            print("deleyad start")
        }
        
        do {
            try videoTrack.insertTimeRange(videoTrackRange, of: vTrack, at: insertTime)
            do {
                if let aTrack = audioTracks.first {
                    let audioTime = aTrack.timeRange.duration // CMTimeMakeWithSeconds(CMTimeGetSeconds(aTrack.timeRange.duration), Int32(NSEC_PER_SEC))
                    let smallestTime = min(videoTrackDuration, audioTime)
                    let audioInsertRange = CMTimeRangeFromTimeToTime(kCMTimeZero, smallestTime)
                    try audioTrack.insertTimeRange(audioInsertRange, of: aTrack , at: insertTime)
                    addedAudio = true
                }
            } catch let err {
                print("\(err)")
            }
            
            
            let videoCompositionInstruction = AVMutableVideoCompositionInstruction()
            videoCompositionInstruction.timeRange = CMTimeRangeMake(insertTime, videoTrackDuration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(insertVideoTrack(vTrack), at: insertTime)
            videoCompositionInstruction.layerInstructions = [layerInstruction]
            
            instructions.append(videoCompositionInstruction)
            
            insertTime = insertTime + videoTrackDuration
            
            if(insertTime.hasBeenRounded){
                print("Was rounded \(insertTime)")
            }
        } catch let err {
            print("\(err)")
        }
    }
    
    private func insertVideoTrack(_ track: AVAssetTrack) -> CGAffineTransform {
        let bounds = CGRect(x: 0, y: 0, width: track.naturalSize.width, height: track.naturalSize.height).applying(track.preferredTransform)
        
        if((track.isPortrait() || track.isSquare())){
            let scaling = size.height / bounds.height
            let scaleToFit = track.preferredTransform.concatenating(CGAffineTransform(scaleX: scaling, y: scaling))
            let moveTransform = CGAffineTransform(translationX: size.width/2 - bounds.width * scaling/2 - bounds.origin.x * scaling, y: -bounds.origin.y * scaling)
            let transform = scaleToFit.concatenating(moveTransform)
            return transform
        } else {
            let scalingHeight = size.height / bounds.height
            let scalingWidth = size.width / bounds.width
            
            let scaling = min(scalingHeight, scalingWidth)
            
            let scaleToFit = track.preferredTransform.concatenating(CGAffineTransform(scaleX: scaling, y: scaling))
            
            let moveTransform = CGAffineTransform(translationX: size.width/2 - bounds.width * scaling/2 - bounds.origin.x * scaling ,y: size.height/2 - bounds.height * scaling/2 - bounds.origin.y * scaling )
            let transform = scaleToFit.concatenating(moveTransform)
            return transform
        }
    }
    
    func videoCompostion(_ preview: Bool = false) -> AVVideoComposition {
        
        let videoComposition = AVMutableVideoComposition()
        
        videoComposition.instructions = instructions
        videoComposition.frameDuration = CMTimeMake(1, 30)
        videoComposition.renderSize = size
        if(!addedAudio){
            mixComposition.removeTrack(audioTrack)
        }
        
        return videoComposition
    }
    
    
    
    public func toSession(_ writeTo: URL) throws -> AVAssetExportSession {
        let encoder = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)!
        //        let encoder = AVAssetExportSession(asset: mixComposition)!
        encoder.outputURL = writeTo
        encoder.outputFileType = AVFileTypeMPEG4
        
        encoder.timeRange = CMTimeRangeMake(kCMTimeZero, mixComposition.duration)
        let composition = videoCompostion()
        encoder.videoComposition = composition
        encoder.canPerformMultiplePassesOverSourceMediaData = true
        return encoder
    }
}


enum FileError : Int {
    case failedToCreateUrl = 1
}

func createFile(_ name: String) throws -> URL  {
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory,.userDomainMask, true)[0]
    let manager = FileManager.default
    do {
        try manager.createDirectory(atPath: documentsPath, withIntermediateDirectories: true, attributes: nil)
    } catch let error as NSError {
        throw error
    }
    
    let outputUrl = (documentsPath as NSString).appendingPathComponent(name)
    do {
        try manager.removeItem(atPath: outputUrl)
    } catch _ as NSError {
        //ignoring error
    }
    
    return URL(fileURLWithPath: outputUrl)
}

func deleteFile(_ name: String) {
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory,.userDomainMask, true)[0]
    let manager = FileManager.default
    do {
        try manager.createDirectory(atPath: documentsPath, withIntermediateDirectories: true, attributes: nil)
        let outputUrl = (documentsPath as NSString).appendingPathComponent(name)
        try manager.removeItem(atPath: outputUrl)
    } catch let error as NSError {
        print(error)
    }
}


public extension AVAssetTrack {
    
    public func isPortrait() -> Bool {
        
        let t = self.preferredTransform;
        // Portrait
        if(t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0){
            return true
        }
        // PortraitUpsideDown
        if(t.a == 0 && t.b == 1.0 && t.c == 1.0 && t.d == 0){
            return true
        }
        
        return false
        
    }
    
    public func isSquare() -> Bool {
        return naturalSize.width == naturalSize.height
    }
    
}

