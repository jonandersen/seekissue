//
//  ViewController.swift
//  SeekIssue
//
//  Created by Jon Andersen on 9/12/17.
//  Copyright © 2017 Jon Andersen. All rights reserved.
//

import UIKit

import UIKit
import AVFoundation
import RxSwift
import Photos
import MediaPlayer
import AVKit

class ViewController: UIViewController {
    private let disposeBag = DisposeBag()
    private let exportManager = ExportManager()
    
    @IBOutlet weak var playerContainer: UIView!
    @IBOutlet weak var videoThumbnailsView: VideoThumbnailsView!
    
    fileprivate var player: Player?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let composition = MutableExportComposition()
        let assets = (1...27).map { (index) -> AVAsset in
            AVAsset(url: URL(fileURLWithPath: Bundle.main.path(forResource: "trim \(index)", ofType: "MOV")!))
            }.sorted { (asset1, asset2) -> Bool in
                asset1.creationDate!.dateValue! < asset2.creationDate!.dateValue!
        }
        
      
        composition.insertAssets(assets)

        let c = composition.getComposition()
        let item = AVPlayerItem(asset: c)
        item.videoComposition = composition.videoCompostion(true)
        player = Player(playerItem: item, containerView: playerContainer)
        player?.delegate = self
        videoThumbnailsView.asset = c
        videoThumbnailsView.videoThumbnailsViewDelegate = self
        
//        let player = AVPlayer(playerItem: item)
//        let playerViewController = AVPlayerViewController()
//        playerViewController.player = player
//        self.present(playerViewController, animated: true)
    }
    
   
    
}


extension ViewController : PlayerDelegate, VideoThumbnailsViewDelegate {
    func moveToTime(_ time: CGFloat) {
        
    }
    
    func timeChanged(_ time: CGFloat) {
        if(player?.playing ?? false){
            videoThumbnailsView.scrollToTime(time: Double(time))

        }
    }
    
    func playing(_ playing: Bool) {
    }
    
    func shouldPlay() -> Bool {
        return true
    }
    
    func videoTumbnailsView(_ videoThumbnailsView: VideoThumbnailsView, didScrollTo time: Double) {
        player?.moveTo(CGFloat(time))
    }
}

