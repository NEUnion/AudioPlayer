//
//  AudioPlayer.swift
//  Visbot
//
//  Created by CXY on 2019/5/21.
//  Copyright © 2019 ubt. All rights reserved.
//

import UIKit
import AVFoundation

class AudioPlayer: NSObject {
    
    private var player: AVAudioPlayer?
    
    typealias ProgressCallBack = (Double) -> Void
    
    private var progressCallBack: ProgressCallBack?
    
    typealias PlayFinished = (Bool) -> Void
    
    private var playFinished: PlayFinished?
    
    private lazy var progressTimer = WeakTimer.scheduledWeakTimer(timeInterval: 0.1, target: self, selector: #selector(_reportProgress(_:)), userInfo: nil, repeats: true)
    
    // MARK: 音量
    var volume: Float = 0 {
        didSet {
            guard let player = player else { return }
            if player.volume != volume {
                player.volume = volume
            }
        }
    }
    
    // MARK: 获取播放进度
    var progress: Double {
        guard let player = player else { return 0 }
        return player.currentTime / player.duration
    }
    
    // MARK: 初始化
    init(data: Data) {
        super.init()
        do {
            self.player = try AVAudioPlayer(data: data)
            self.player?.volume = 0.5
            self.player?.delegate = self
        } catch {
            print(error.localizedDescription)
        }
    }


    // MARK: 播放并上报进度
    func play(_ callback: ProgressCallBack? = nil) {
        guard let player = player else { return }
        progressCallBack = callback
        let ret = player.play()
        if ret {
            progressTimer.fireDate = Date()
        } else {
            print("play error!")
        }
    }
    
    func playFinished(_ callback: @escaping PlayFinished) {
        playFinished = callback
    }
    
    // MARK: 暂停
    func pause() {
        player?.pause()
        progressTimer.fireDate = Date.distantFuture
    }
    
    // MARK: 停止
    func stop() {
        player?.stop()
        progressTimer.invalidate()
    }
    
    @objc private func _reportProgress(_ timer: Timer) {
        guard let player = player else { return }
        // currentTime
        let currentTime = player.currentTime
        // duration
        let totalTime = player.duration
        // progress
        let progress = currentTime / totalTime
        progressCallBack?(progress)
    }

    // MARK: 设置进度
    func updateProgress(_ rate: Double) {
        guard rate >= 0 && rate <= 1, let player = player else {
            return
        }
        player.currentTime = player.duration * rate
    }
    
}

// MARK: AVAudioPlayerDelegate
extension AudioPlayer: AVAudioPlayerDelegate {
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        progressTimer.invalidate()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        progressTimer.invalidate()
        playFinished?(flag)
    }

}



extension AudioPlayer {
    
    // MARK: 获取专辑图片
    func albumImage() -> UIImage? {
        guard let url = player?.url else { return nil }
        let asset = AVURLAsset(url: url)
        guard let format = asset.availableMetadataFormats.first else { return nil }
        let items = asset.metadata(forFormat: format)
        let targets = items.filter { (item) -> Bool in
            return item.commonKey?.rawValue == "artwork"
        }
        if let target = targets.first, let data = target.value as? Data {
            return UIImage(data: data)
        }
        return nil
    }
}

