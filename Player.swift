//
//  Player.swift
//  Visbot
//
//  Created by CXY on 2019/5/28.
//  Copyright © 2019 ubt. All rights reserved.
//

import Alamofire

private func PlayerLog(_ items: Any...) {
    #if DEBUG
    print(items)
    #endif
}

enum PlayerStatus {
    case unknown
    case buffering
    case prepareToPlay
    case finished
    case failed
    case networkError
}

class Player: NSObject {
    
    private var queuePlayer: AVQueuePlayer?
    
    private let reachabilityManager = NetworkReachabilityManager()
    
    private(set) var playerItems = [AVPlayerItem]()
    
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
    
    private(set) var playerStatus = PlayerStatus.unknown {
        didSet {
            playerStateChanged?(playerStatus)
        }
    }
    
    var isPlaying: Bool {
        return playerStatus == .prepareToPlay
    }
    
    var itemDuration: Double {
        guard let item = queuePlayer?.currentItem else {
            return 0
        }
        return CMTimeGetSeconds(item.duration)
    }
    
    private var itemTime: Double {
        guard let item = queuePlayer?.currentItem else {
            return 0
        }
        return CMTimeGetSeconds(item.currentTime())
    }
    
    
    var itemDurationByMinutes: String {
        return Int(ceil(itemDuration)).minutesFormatString
    }
    
    var itemTimeByMinutes: String {
        return Int(ceil(itemTime)).minutesFormatString
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
    
    override convenience init() {
        self.init(urlString: nil)
    }

    convenience init(urlString: String?) {
        if let url = urlString {
            self.init(strings: [url])
        } else {
            self.init(strings: nil)
        }
        
    }
    
    init(strings: [String]?) {
        super.init()
        if let strings = strings, let items = itemsForURLs(strings), !items.isEmpty {
            playerItems = items
        }
        queuePlayer = AVQueuePlayer(items: playerItems)
        queuePlayer?.actionAtItemEnd = .pause
        if #available(iOS 10.0, *) {
            queuePlayer?.automaticallyWaitsToMinimizeStalling = false
        } else {
            // Fallback on earlier versions
        }
        
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

    func appendItems(_ strings: [String]) {
        if let items = itemsForURLs(strings), !items.isEmpty {
            playerItems.append(contentsOf: items)
            guard let player = queuePlayer else { return }
            items.forEach { (item) in
                if player.canInsert(item, after: nil) {
                    player.insert(item, after: nil)
                }
            }
        }
    }
    
    func removeItem(_ url: String) {
        if let items = itemsForURLs([url]), !items.isEmpty {
            guard let player = queuePlayer else { return }
            playerItems.removeAll { (item) -> Bool in
                return item.mc_URL.absoluteString.elementsEqual(url)
            }
            let allItems = player.items()
            for item in allItems {
                if item.mc_URL.absoluteString.elementsEqual(url) {
                    player.remove(item)
                }
            }

        }
    }
    
    func clearPlayItems() {
        playerItems.removeAll()
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
    
    func report(playProgress: ProgressCallBack? = nil, cacheProgress: ProgressCallBack? = nil, currentTime: ProgressCallBack? = nil, duration: ProgressCallBack? = nil, playFinished: PlayBack? = nil) {
        self.playProgress = playProgress
        self.cacheProgress = cacheProgress
        self.playTimeCallBack = currentTime
        self.playFinished = playFinished
        self.durationConfirmed = duration
    }

    
    private func internalPlay(atIndex index: Int) {
        guard let player = queuePlayer, player.items().indices.contains(index) else {
            PlayerLog("player index error!")
            return
        }
        if index == indexOfPlayingItem + 1 {
            player.advanceToNextItem()
            indexOfPlayingItem = index
            return
        }
        player.removeAllItems()
        let items = playerItems
        for i in index..<items.count {
            let item = items[i]
            if player.canInsert(item, after: nil) {
                item.seek(to: .zero)
                player.insert(item, after: nil)
            }
        }
        
        indexOfPlayingItem = index
    }
    
    // MARK: 播放
    
    func play(atIndex index: Int, stateChanged: PlayerStateChanged? = nil) {
        guard let player = queuePlayer, player.items().indices.contains(index) else {
            PlayerLog("player index error!")
            return
        }
        playerStateChanged = stateChanged
        internalPlay(atIndex: index)
        addObservers()
    }
    
    func quickPlay(url: String, stateChanged: PlayerStateChanged? = nil) {
        if let items = itemsForURLs([url]), !items.isEmpty {
            removeObservers()
            queuePlayer?.replaceCurrentItem(with: items.first!)
            playerStateChanged = stateChanged
            addObservers()
        }
    }
    
    func play() {
        play(atIndex: 0, stateChanged: nil)
    }

    // MARK: 暂停
    
    func pause() {
        queuePlayer?.pause()
    }
    
    func continuePlay() {
        queuePlayer?.play()
    }
    
    private func playNextAndRemoveCurrent() {
        if let item = queuePlayer?.currentItem {
            queuePlayer?.remove(item)
        }
        playNext()
    }
    
    private func playNext() {
        internalPlay(atIndex: indexOfPlayingItem + 1)
    }
    
    // MARK: 停止

    func destroy() {
        queuePlayer?.pause()
        queuePlayer?.currentItem?.cancelPendingSeeks()
        queuePlayer?.currentItem?.asset.cancelLoading()
        queuePlayer?.removeAllItems()
        playerItems.removeAll()
        removeObservers()
    }

    
    private func addObservers() {
        addAVPlayerObserver()
        self.startApplicationObserver()
    }

    private func removeObservers() {
        removeAVPlayerObserver()
        endApplicationObserver()
    }
    
    // MARK: 释放
    
    deinit {
        PlayerLog("\(self)", #function)
//        endNetworkReachabilityObserver()
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
    private func addAVPlayerObserver() {
        guard let item = queuePlayer?.currentItem else { return }
        item.addObserver(self, forKeyPath: "status", options: .new, context: nil)
        item.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: nil)
        addPeriodicTimeObserver()
        
        // 监听播放完成
        NotificationCenter.default.addObserver(self, selector: #selector(itemFinished(_:)), name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    @objc private func itemFinished(_ notif: Notification) {
        PlayerLog("播放完成！")
        playerStatus = .finished
        playTimeCallBack?(itemDuration)
        // 播放完成回到开始位置
//        updateProgress(0) { [weak self](ret) in
//            guard let strongSelf = self else {
//                self?.playFinished?(true)
//                return
//            }
//            strongSelf.playFinished?(true)
//        }
        
    }
    
    private func removeAVPlayerObserver() {
        guard let item = queuePlayer?.currentItem else { return }
        item.removeObserver(self, forKeyPath: "status")
        item.removeObserver(self, forKeyPath: "loadedTimeRanges")
        removePeriodicTimeObserver()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    // MARK: status & loadedTimeRanges
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let path = keyPath, let dict = change, let duration = queuePlayer?.currentItem?.duration, let item = queuePlayer?.currentItem else { return }
        
        if path.elementsEqual("status") {
            if let value = dict[NSKeyValueChangeKey.newKey] as? Int {
                let status = AVPlayerItem.Status(rawValue: value)
                if status == AVPlayerItem.Status.readyToPlay {// 显示总时长
                    queuePlayer?.play()
                    playerStatus = .prepareToPlay
                    PlayerLog("---》开始播放")
                    // 这里获取总时长总是有问题
                    if duration != CMTime.indefinite {
                        let total = CMTimeGetSeconds(duration)
                        PlayerLog("duraion =====  \(total)")
                    } else {
                        PlayerLog("duraion =====  NAN")
                    }
                } else if status == AVPlayerItem.Status.failed {
                    PlayerLog("---》播放器状态错误！")
                    playerStatus = .failed
                }
            }
            
        } else if path.elementsEqual("loadedTimeRanges") {// 计算缓存时长
            let array = item.loadedTimeRanges
            guard let timeRange = array.first?.timeRangeValue else { return }
            let start = CMTimeGetSeconds(timeRange.start)
            let length = CMTimeGetSeconds(timeRange.duration)
            // 缓冲总长度
            let totalBuffer = start + length
            let videoLength = CMTimeGetSeconds(duration)
            let ratio = totalBuffer/videoLength
            //  print("缓冲总长度:\(totalBuffer), 视频总长度:\(videoLength), 进度：\(ratio)")
            // 设置缓存进度
            cacheProgress?(ratio)
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
        startApplicationObserver()
    }
    
    // MARK: 停止网络状态监听
    
    private func endNetworkReachabilityObserver() {
        reachabilityManager?.stopListening()
    }
    
    // MARK: App状态监听
    
    private func startApplicationObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(applicaitonEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicaitonEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(avSessionInterrupt(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    
    private func endApplicationObserver() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
    }
    
    
    @objc private func applicaitonEnterBackground(_ notif: Notification) {
        
    }
    
    @objc private func applicaitonEnterForeground(_ notif: Notification) {
        
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

