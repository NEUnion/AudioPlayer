//
//  Player.swift
//  Visbot
//
//  Created by CXY on 2019/5/28.
//  Copyright © 2019 ubt. All rights reserved.
//

import Alamofire

private func PlayerLog<T>(_ message:T, file: String = #file, funcName: String = #function, lineNum: Int = #line) {
    #if DEBUG
    let file = (file as NSString).lastPathComponent;
    // 文件名：行数---要打印的信息
    print("\(file):(\(lineNum))--\(message)");
    #endif
}

enum PlayerStatus {
    case unknown
    case buffering
    case prepareToPlay
    case pause
    case continueToPlay
    case finished
    case failed
    case networkError
}

class Player: NSObject {
    
    private var queuePlayer: AVQueuePlayer?
    
    private let reachabilityManager = NetworkReachabilityManager()
    
    private var indexOfPlayingItem = 0
    
    private var timeObserver: Any?
    
    typealias ProgressCallBack = (Double) -> Void
    
    private var playTimeCallBack: ProgressCallBack?
    
    private var playProgress: ProgressCallBack?
    
    private var cacheProgress: ProgressCallBack?
    
    typealias PlayBack = (Bool) -> Void
    
    private var playFinished: PlayBack?
    
    private var durationConfirmed: ProgressCallBack?
    
    typealias PlayerStateChanged = (PlayerStatus) -> Void
    
    private var playerStateChanged: PlayerStateChanged?
    
    private(set) var currentAVPlayerItem: AVPlayerItem?
    
    private(set) var playerStatus = PlayerStatus.unknown {
        didSet {
            PlayerLog("\(self) Player state = \(playerStatus)")
            playerStateChanged?(playerStatus)
        }
    }
    
    private var isPlayingBeforeEnterBackground = false
    
    var isInBackground = false
    
    var isPlaying: Bool {
        if #available(iOS 10.0, *) {
            return queuePlayer?.timeControlStatus == .playing
        } else {
            // Fallback on earlier versions
            return queuePlayer?.rate != 0.0
        }
    }
    
    var itemDuration: Double {
        guard let item = queuePlayer?.currentItem else {
            return 0
        }
        if item.duration != CMTime.indefinite {
            return CMTimeGetSeconds(item.duration)
        }
        return 0
    }
    
    private var itemTime: Double {
        guard let item = queuePlayer?.currentItem else {
            return 0
        }
        if item.currentTime() != CMTime.indefinite {
            return CMTimeGetSeconds(item.currentTime())
        }
        return 0
    }
    
    // MARK: 获取播放进度
    
    var progress: Double {
        guard itemDuration > 0 else {
            return 0
        }
        return itemTime / itemDuration
    }
    
    // MARK: 音量
    
    var volume: Float = 0 {
        didSet {
            guard let player = queuePlayer else { return }
            if player.volume != volume {
                player.volume = volume
            }
        }
    }
    
    // MARK: 初始化
    
    override init() {
        super.init()
        queuePlayer = AVQueuePlayer()
        queuePlayer?.actionAtItemEnd = .pause
        if #available(iOS 10.0, *) {
            queuePlayer?.automaticallyWaitsToMinimizeStalling = false
        } else {
            // Fallback on earlier versions
        }
        // 监听播放完成
        NotificationCenter.default.addObserver(self, selector: #selector(itemFinished(_:)), name: .AVPlayerItemDidPlayToEndTime, object: queuePlayer?.currentItem ?? nil)
        NotificationCenter.default.addObserver(self, selector: #selector(itemErrorOccurred(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        addApplicationObserver()
    }
    
    
    private func itemsForURLs(_ strings: [String]) -> [AVPlayerItem]? {
        guard !strings.isEmpty else {
            PlayerLog("url error!")
            return nil
        }
        
        let valid = strings.filter { (str) -> Bool in
            return URL(string: str) != nil
        }
        
        guard valid.count == strings.count else {
            PlayerLog("url error!")
            return nil
        }
        
        var ret: [AVPlayerItem]? = nil
        do {
            ret = try strings.map { (item) -> AVPlayerItem in
                return try AVPlayerItem.mc_playerItem(withRemoteURL:  URL(string: item)!)
            }
        } catch  {
            print(error)
        }
        return ret
    }
    
    
    // MARK: 设置进度
    
    func updateProgress(_ rate: Double, finished: PlayBack? = nil) {
        guard rate >= 0 && rate <= 1, let player = queuePlayer else {
            finished?(false)
            return
        }
        
        let begintime = CMTimeMake(value: Int64(lround(itemDuration * rate)), timescale: 1)
        player.seek(to: begintime, completionHandler: {(fin) in
            finished?(fin)
        })
    }
    
    func report(playProgress: ProgressCallBack? = nil, cacheProgress: ProgressCallBack? = nil, currentTime: ProgressCallBack? = nil, duration: ProgressCallBack? = nil) {
        self.playProgress = playProgress
        self.cacheProgress = cacheProgress
        self.playTimeCallBack = currentTime
        self.durationConfirmed = duration
    }
    
    
    // MARK: 播放
    
    func quickPlay(url: String, stateChanged: PlayerStateChanged? = nil) {
        if let items = itemsForURLs([url]), !items.isEmpty {
            queuePlayer?.pause()
            queuePlayer?.currentItem?.cancelPendingSeeks()
            queuePlayer?.currentItem?.asset.cancelLoading()
            removeAVPlayerItemObserver()
            queuePlayer?.replaceCurrentItem(with: items.first)
            addAVPlayerItemObserver()
            playerStateChanged = stateChanged
        }
    }
    
    // MARK: 暂停
    
    func pause() {
        queuePlayer?.pause()
        playerStatus = .pause
    }
    
    func continuePlay() {
        queuePlayer?.play()
        playerStatus = .continueToPlay
    }
    
    
    // MARK: 停止
    
    private func destroy() {
        queuePlayer?.pause()
        queuePlayer?.currentItem?.cancelPendingSeeks()
        queuePlayer?.currentItem?.asset.cancelLoading()
        removeObservers()
    }
    
    
    private func addObservers() {
        addAVPlayerItemObserver()
        addApplicationObserver()
    }
    
    private func removeObservers() {
        removeAVPlayerItemObserver()
        removeApplicationObserver()
    }
    
    // MARK: 释放
    
    deinit {
        PlayerLog("\(self) deinit")
        //        endNetworkReachabilityObserver()
        destroy()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        removeApplicationObserver()
    }
}

extension Player {
    
    // MARK: 监控视频播放进度
    
    private func addPeriodicTimeObserver() {
        timeObserver = queuePlayer?.addPeriodicTimeObserver(forInterval: CMTimeMakeWithSeconds(0.1, preferredTimescale: Int32(NSEC_PER_SEC)), queue: DispatchQueue.main) { [weak self](time) in
            guard let strongSelf = self else { return }
            let duration = strongSelf.itemDuration
            if duration > 0 {
                strongSelf.durationConfirmed?(duration)
                strongSelf.playProgress?(strongSelf.progress)
                strongSelf.playTimeCallBack?(strongSelf.itemTime)
            }
        }
    }
    
    private func removePeriodicTimeObserver() {
        if let observer = timeObserver {
            queuePlayer?.removeTimeObserver(observer)
        }
    }
    
    // 监听AVPlayerItem对象的status/loadedTimeRanges属性变化，status对应播放状态，loadedTimeRanges网络缓冲状态，当loadedTimeRanges的改变时，每缓冲一部分数据就会更新此属性，可以获得本次缓冲加载的视频范围（包含起始时间、本次网络加载时长）
    private func addAVPlayerItemObserver() {
        guard let item = queuePlayer?.currentItem else { return }
        item.addObserver(self, forKeyPath: "status", options: .new, context: nil)
        item.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: nil)
        item.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: .new, context: nil)
        item.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
        addPeriodicTimeObserver()
    }
    
    @objc private func itemErrorOccurred(_ notif: Notification) {
        guard let currentItem = queuePlayer?.currentItem else { return }
        if let item = notif.object as? AVPlayerItem, item == currentItem {
            PlayerLog("\(self) \(currentItem) 播放失败！")
        }
    }
    
    // MARK: 播放完成
    
    @objc private func itemFinished(_ notif: Notification) {
        guard let currentItem = queuePlayer?.currentItem else { return }
        if let item = notif.object as? AVPlayerItem, item == currentItem, item.isPlaybackLikelyToKeepUp {
            PlayerLog("\(self) \(String(describing: currentItem.mc_URL)) 播放完成！")
            playerStatus = .finished
        }
        
    }
    
    private func removeAVPlayerItemObserver() {
        guard let item = queuePlayer?.currentItem else { return }
        item.removeObserver(self, forKeyPath: "status")
        item.removeObserver(self, forKeyPath: "loadedTimeRanges")
        item.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        item.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        removePeriodicTimeObserver()
    }
    
    // MARK: status & loadedTimeRanges
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let path = keyPath, let dict = change, let item = queuePlayer?.currentItem else { return }
        
        if path.elementsEqual("status") {
            if let value = dict[NSKeyValueChangeKey.newKey] as? Int {
                let status = AVPlayerItem.Status(rawValue: value)
                if status == AVPlayerItem.Status.readyToPlay {
                    if !isInBackground {
                        queuePlayer?.play()
                        // redayToPlay状态下获取总时长仍有可能是NAN
                        playerStatus = .prepareToPlay
                        PlayerLog("\(self) 开始播放")
                    }
                    
                    if item.duration != CMTime.indefinite {
                        let total = CMTimeGetSeconds(item.duration)
                        PlayerLog("\(self) duraion: \(total)")
                    } else {
                        PlayerLog("\(self) duraion: NAN")
                    }
                    
                } else if status == AVPlayerItem.Status.failed {
                    PlayerLog("\(self) 播放器状态错误！")
                    playerStatus = .failed
                }
            }
            
        } else if path.elementsEqual("loadedTimeRanges") {
            // 计算缓存时长
            let array = item.loadedTimeRanges
            guard let timeRange = array.first?.timeRangeValue else { return }
            let start = CMTimeGetSeconds(timeRange.start)
            let length = CMTimeGetSeconds(timeRange.duration)
            // 缓冲总长度
            let totalBuffer = start + length
            let videoLength = CMTimeGetSeconds(item.duration)
            let ratio = totalBuffer/videoLength
            // 设置缓存进度
            cacheProgress?(ratio)
        } else if path.elementsEqual("playbackBufferEmpty") {
            if let playbackBufferEmpty = dict[NSKeyValueChangeKey.newKey] as? Bool {
                PlayerLog("\(self) playbackBufferEmpty = \(playbackBufferEmpty)")
                if playbackBufferEmpty {
                    playerStatus = .buffering
                }
            }
        } else if path.elementsEqual("playbackLikelyToKeepUp") {
            if let playbackLikelyToKeepUp = dict[NSKeyValueChangeKey.newKey] as? Bool {
                PlayerLog("\(self) playbackLikelyToKeepUp = \(playbackLikelyToKeepUp)")
                if playbackLikelyToKeepUp {
                    if queuePlayer?.rate == 0 && playerStatus != .pause && playerStatus != .finished && playerStatus != .failed && !isInBackground {
                        PlayerLog("\(self) 缓冲足够可以播放")
                        queuePlayer?.play()
                        playerStatus = .continueToPlay
                    }
                } else {
                    if (!NetworkingRequest.shared.isReachable() || NetworkingRequest.shared.isRestricted()) && queuePlayer?.rate == 0 {
                        queuePlayer?.pause()
                        playerStatus = .pause
                    }
                }
            }
        }
        
    }
}


extension Player {
    
    // MARK: 开始网络状态监听
    
    private func startNetworkReachabilityObserver() {
        reachabilityManager?.listener = { [weak self]status in
            guard let _ = self else { return }
            switch status {
            case .notReachable:
                self?.playerStatus = .networkError
                break
            case .unknown :
                // print("It is unknown whether the network is reachable")
                break
            case .reachable(.ethernetOrWiFi):
                // print("The network is reachable over the WiFi connection")
                break
            case .reachable(.wwan):
                // print("The network is reachable over the WWAN connection")
                break
                
            }
        }
        
        // start listening
        reachabilityManager?.startListening()
    }
    
    // MARK: 停止网络状态监听
    
    private func endNetworkReachabilityObserver() {
        reachabilityManager?.stopListening()
    }
    
    // MARK: App状态监听
    
    private func addApplicationObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(applicaitonEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicaitonEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(avSessionInterrupt(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    
    private func removeApplicationObserver() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
    }
    
    
    @objc private func applicaitonEnterBackground(_ notif: Notification) {
        PlayerLog("\(self) applicaitonEnterBackground")
        if isPlaying {
            queuePlayer?.pause()
            playerStatus = .pause
            isPlayingBeforeEnterBackground = true
            PlayerLog("\(self) 进入后台暂停播放")
        } else {
            isPlayingBeforeEnterBackground = false
        }
    }
    
    @objc private func applicaitonEnterForeground(_ notif: Notification) {
        PlayerLog("\(self) applicaitonEnterForeground")
        if isPlayingBeforeEnterBackground {
            queuePlayer?.play()
            playerStatus = .continueToPlay
            PlayerLog("\(self) 进入前台恢复播放")
        }
    }
    
    
    @objc private func restorePlayingState() {
        
    }
    
    @objc private func avSessionInterrupt(_ notif: Notification) {
        guard let info = notif.userInfo, let interType = info[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        
        switch interType {
        case AVAudioSession.InterruptionType.began.rawValue:
            // 暂停播放,实际上已经暂停了
            
            break
        case AVAudioSession.InterruptionType.ended.rawValue:
            break
        default:
            break
        }
        
        guard let secReason = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
        switch secReason {
        case AVAudioSession.InterruptionOptions.shouldResume.rawValue:
            perform(#selector(restorePlayingState), with: nil, afterDelay: 1.5)
            break
        default:
            break
        }
    }
}


extension Int {
    
    var minutesFormatString: String {
        let seconds = self%60
        let minutes = (self/60)%60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var hoursFormatString: String {
        let seconds = self%60
        let minutes = (self/60)%60
        let hours = self/3600
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
}

