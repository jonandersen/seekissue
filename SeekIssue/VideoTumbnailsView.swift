//
//  VideoThumbnailsView.swift
//  leapsecond
//
//  Created by Jon Andersen on 9/9/17.
//  Copyright © 2017 Andersen. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

protocol VideoThumbnailsViewDelegate: class {
    func videoTumbnailsView(_ videoThumbnailsView: VideoThumbnailsView, didScrollTo time: Double)
}

class VideoThumbnailsView: UIScrollView, UIScrollViewDelegate {
    
    weak var videoThumbnailsViewDelegate: VideoThumbnailsViewDelegate?
    
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = false
        bounces = false
        
        layer.masksToBounds = true
        
        self.delegate = self
    }
    
    fileprivate var scrollContentWidth: CGFloat = 0.0
    var asset: AVAsset! {
        didSet {
            duration = CMTimeGetSeconds(asset.duration)
            thumbImageProcessing(asset: asset!, thumbWidth: self.frame.height)
        }
    }
    
    fileprivate var duration: Float64 = 0.0
    fileprivate var currentTime: Double = 0.0
    
    fileprivate func thumbImageProcessing(asset: AVAsset, thumbWidth: CGFloat){
        let range = 0...Int(duration)
        
        let thumbnails = range.map { index -> UIImageView in
            let thumbXCoords = CGFloat(index) * thumbWidth
            let thumbnailFrame = CGRect(x: thumbXCoords,y: 0.0, width: thumbWidth, height: thumbWidth)
            let thumbnailView = UIImageView(frame: thumbnailFrame)
            thumbnailView.contentMode = .scaleAspectFill
            thumbnailView.backgroundColor = UIColor.clear
            thumbnailView.tag = index
            
            self.scrollContentWidth = self.scrollContentWidth + thumbWidth
            self.addSubview(thumbnailView)
            
            return thumbnailView
        }
        
        self.contentSize = CGSize(
            width: Double(self.scrollContentWidth),
            height: Double(self.frame.size.height))
        
        
        self.setContentOffset(CGPoint(x: 0.0, y: 0.0), animated: true)
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            thumbnails.forEach { thumbnailView in
                let thumbnail =  self.generateVideoThumbs(asset, second: Double(thumbnailView.tag), thumbWidth: CGFloat(thumbWidth))
                DispatchQueue.main.async {
                    thumbnailView.image = thumbnail
                }
            }
        }
    }
    
    func scrollToTime(time: Double){
        currentTime  = time
        delegate = nil
        contentOffset.x = contentSize.width * CGFloat(currentTime / (max(duration, 1.0)))
        delegate = self
        print("scrollTime: \(currentTime))")
        
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let percentage = scrollView.contentOffset.x / max(contentSize.width, 1.0)
        currentTime = duration * Double(percentage)
        print("time: \(currentTime))")
        videoThumbnailsViewDelegate?.videoTumbnailsView(self, didScrollTo: currentTime)
    }
    
    fileprivate func generateVideoThumbs(_ asset: AVAsset, second: Double, thumbWidth: CGFloat) -> UIImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let scale = UIScreen.main.scale * 2
        generator.maximumSize = CGSize(width: thumbWidth * scale, height: thumbWidth * scale)
        generator.appliesPreferredTrackTransform = false
        let thumbTime = CMTimeMakeWithSeconds(second, 1)
        do {
            let ref = try generator.copyCGImage(at: thumbTime, actualTime: nil)
            return UIImage(cgImage: ref)
        }catch {
            print(error)
        }
        return UIImage()
    }
}

