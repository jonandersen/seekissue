//
//  AVPlayer.swift
//  LeapSecond
//
//  Created by Jon Andersen on 7/18/15.
//  Copyright (c) 2015 Andersen. All rights reserved.
//

import Foundation
import AVFoundation
import FontAwesome_swift

public protocol PlayerDelegate: class{
    func moveToTime(_ time: CGFloat) -> ()
    func timeChanged(_ time: CGFloat) -> ()
    func playing(_ playing: Bool) -> ()
    func shouldPlay() -> Bool
}

class Player: AVPlayer, UIGestureRecognizerDelegate {
    weak var delegate: PlayerDelegate?
    
    var playing: Bool = false
    private var trimPlaying: Bool = false
    private var endTime: CGFloat = 0.0
    private var startTime: CGFloat = 0.0
    private var timeObserver: AnyObject?
    private weak var view: UIView!
    private var playerLayer: AVPlayerLayer?
    private var playButton: UIButton = UIButton()
    private var rotation: CGFloat = 0.0
    private var autoPlay: Bool = false
    private var playerItem: AVPlayerItem?
    private var seeking = false
    private var isReadyToPlay = false
    
    override init() {
        super.init()
    }
    
    public init(playerItem item: AVPlayerItem!, containerView: UIView, rotation: CGFloat = 0.0, autoPlay: Bool = false) {
        super.init(playerItem: item)
        self.autoPlay = autoPlay
        self.configurePeriodicTimeObserving()
        self.view = containerView
        self.rotation = rotation
        
        
        item.seekingWaitsForVideoCompositionRendering = true
        
        
        playButton.titleLabel?.font = UIFont.fontAwesome(ofSize: 40)
        playButton.setTitle(String.fontAwesomeIcon(name: .play), for: .normal)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playButtonClicked(_:)), for: UIControlEvents.touchUpInside)
        playButton.isHidden = true
        
        self.view.addSubview(playButton)
        let centerYConstraint = NSLayoutConstraint(item: playButton, attribute: .centerY, relatedBy: .equal, toItem: self.view, attribute: .centerY, multiplier: 1.0, constant: 0.0)
        let centerXConstraint = NSLayoutConstraint(item: playButton, attribute: .centerX, relatedBy: .equal, toItem: self.view, attribute: .centerX, multiplier: 1.0, constant: 0.0)
        self.view.addConstraints([centerYConstraint, centerXConstraint])
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
        playButton.isHidden = false
        
        
        playerLayer = AVPlayerLayer(player: self)
        playerLayer?.transform = CATransform3DMakeRotation(rotation, 0, 0.0, 1.0)
        playerLayer!.frame = self.view.bounds
        view.layer.insertSublayer(playerLayer!, below: playButton.layer)
        
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        containerView.addGestureRecognizer(tap)
        
        
        NotificationCenter.default.addObserver(self, selector: (#selector(pause(_:))), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: item)
        NotificationCenter.default.addObserver(self, selector: (#selector(pause(_:))), name: NSNotification.Name.AVPlayerItemFailedToPlayToEndTime, object: item)
        NotificationCenter.default.addObserver(self, selector: (#selector(pause(_:))), name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { () -> Void in
            self.playButton.isHidden = false
        }
        currentItem?.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions(), context: nil)
        
    }
    
    func enable(_ enabled: Bool)  {
        self.playButton.isHidden = !enabled
        self.view.isUserInteractionEnabled = enabled
    }
    
    func clean() {
        self.pause()
        self.playButton.removeFromSuperview()
        self.playButton.removeTarget(self, action: #selector(playButtonClicked(_:)), for: UIControlEvents.touchUpInside)
        self.playerLayer?.removeFromSuperlayer()
        self.playerLayer = nil
        if let timeObserver = self.timeObserver{
            removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        delegate = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        self.clean()
        playerItem = nil
        currentItem?.removeObserver(self, forKeyPath: "status", context: nil)
    }
    
    func pause(_ notification: Notification) {
        self.seek(to: CMTimeMakeWithSeconds(Float64(startTime), 60), toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
        self.delegate?.moveToTime(startTime)
        self.delegate?.timeChanged(startTime)
        self.pause()
    }
    
    
    func handleTap(_ sender: UITapGestureRecognizer) {
        if(playing){
            playButton.animateShow(true, icon: .play)
            pause()
        }
    }
    
    func playButtonClicked(_ button: UIButton) {
        if(playing) {
            pause()
        }else{
            if(delegate?.shouldPlay() ?? true){
                play()
            }
        }
    }
    
    
    private func configurePeriodicTimeObserving() -> () {
        let mainQueue = DispatchQueue.main
        self.timeObserver = self.addPeriodicTimeObserver(forInterval: CMTimeMake(33, 1000), queue: mainQueue, using: {[weak self] (currentTime) -> Void in
            guard let this = self else {
                return
            }
            let time: CGFloat = CGFloat(CMTimeGetSeconds(currentTime))
            if(this.playing){
                this.delegate?.moveToTime(time)
                this.delegate?.timeChanged(time)
            }
            if(this.trimPlaying && time >= this.endTime){
                let moveTo = this.startTime
                this.pause()
                this.seek(to: CMTimeMakeWithSeconds(Float64(moveTo), 60), toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
                this.delegate?.moveToTime(moveTo)
                this.delegate?.timeChanged(moveTo)
            }
        }) as AnyObject?
    }
    
    func layout() {
        UIView.animate(withDuration: 0.25, animations: { () -> Void in
            if let playerLayer = self.playerLayer {
                playerLayer.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.height)
            }
            self.view.layoutIfNeeded()
        })
    }
    
    func moveTo(_ start: CGFloat) {
        if let item = self.currentItem, !playing, !seeking  {
            seeking = true
            self.startTime = min(start, CGFloat(CMTimeGetSeconds(item.duration)))
            print("starTime: \(startTime)")
            let timescale = item.duration.timescale
            let seekToTime = CMTimeMakeWithSeconds(Double(startTime), timescale)
            if(seekToTime == kCMTimeInvalid){
                seeking = false
                return
            }
            var tolerance = CMTimeMakeWithSeconds(0.01, timescale)
            //            tolerance = kCMTimeZero
            //            seek(to: seekToTime, completionHandler: { (finished) in
            //                if(finished){
            //                    self.seeking = false
            //                    self.delegate?.timeChanged(start)
            //                }
            //            })
            seek(to: seekToTime, toleranceBefore: tolerance, toleranceAfter: tolerance, completionHandler: { finished in
                if(finished){
                    self.seeking = false
                    self.delegate?.timeChanged(start)
                }
            })
        }
    }
    
    func playSection(_ start: CGFloat, end: CGFloat) {
        if(playing){
            pause()
            return
        }
        startTime = start
        endTime = end
        trimPlaying = true
        play()
    }
    
    
    
    override func play() {
        if(isReadyToPlay){
            playButton.animateShow(false, icon: .pause)
            playing = true
            delegate?.playing(true)
            super.play()
        }
    }
    
    override func pause() {
        super.pause()
        playButton.animateShow(true, icon: .play)
        trimPlaying = false
        playing = false
        delegate?.playing(false)
    }
    
    @objc
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if currentItem?.status == AVPlayerItemStatus.readyToPlay {
            isReadyToPlay = true
            if(autoPlay){
                autoPlay = false
                play()
            }
        }
    }
    
}

public extension UIButton {
    public func animateShow(_ show: Bool, icon: FontAwesome) {
        setTitle(String.fontAwesomeIcon(name: icon), for: .normal)
        animateShow(show)
    }
    
    func fontAwesomeWithTitle(icon: FontAwesome, title: String, color: UIColor) {
        let buttonString = "\(String.fontAwesomeIcon(name: icon)) \n\(title)"
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        paragraphStyle.alignment = .center
        
        let buttonStringAttributed = NSMutableAttributedString(string: buttonString, attributes: [NSFontAttributeName:UIFont(name: "HelveticaNeue", size: 15.00)!, NSForegroundColorAttributeName: color])
        buttonStringAttributed.addAttribute(NSFontAttributeName, value:  UIFont.fontAwesome(ofSize: 22),  range: NSRange(location: 0,length: 1))
        buttonStringAttributed.addAttribute(NSParagraphStyleAttributeName, value:paragraphStyle, range:NSMakeRange(0, buttonStringAttributed.length))
        
        titleLabel?.textAlignment = .center
        titleLabel?.numberOfLines = 2
        setAttributedTitle(buttonStringAttributed, for: .normal)
    }
}

extension UIView {
    
    
    func animateShow(_ show: Bool) {
        self.isHidden = false
        if(show){
            UIView.animate(withDuration: 0.3, animations: { () -> Void in
                self.alpha = 1
            })
        }else{
            UIView.animate(withDuration: 0.3, animations: { () -> Void in
                self.alpha = 0
            }, completion: { (finished) -> Void in
                self.isHidden = true
            })
        }
    }
}


