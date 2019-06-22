//
//  AudioPlayerManager.swift
//  Visbot
//
//  Created by CXY on 2019/5/22.
//  Copyright © 2019 CXY. All rights reserved.
//


/// 播放器管理及数据缓存管理
class AudioPlayerManager: NSObject {
    
    static let shared = AudioPlayerManager()
    
    private override init() {
        super.init()
    }
    
    /// about cache
    private lazy var downloadQueue = DispatchQueue.global()
    
    private let allowedDiskSize = 100 * 1024 * 1024
    
    private let diskCachePath = "mp3Cache"
    
    private lazy var cache = URLCache(memoryCapacity: 0, diskCapacity: allowedDiskSize, diskPath: diskCachePath)
    
    private lazy var playerHash = [String: AudioPlayer]()
    
    func prepareDataForPlay(_ path: String, ready: ((AudioPlayer?)->Void)? = nil) {
        guard !IsNilOrEmptyString(path) else {
            ready?(nil)
            return
        }
        downloadQueue.async {
            self.downloadContent(fromUrlString: path, completionHandler: { (result) in
                
                switch result {
                    
                case .success(let data):
                    // handle data
                    let audioPlayer = AudioPlayer(data: data)
                    DispatchQueue.main.async {
                        self.playerHash[path] = audioPlayer
                        if ready == nil {
                            audioPlayer.play()
                        }
                        ready?(audioPlayer)
                    }
                    
                case .failure(let error):
                    debugPrint(error.localizedDescription)
                    DispatchQueue.main.async {
                        ready?(nil)
                    }
                }
            })
            
        }
    }
    
    
    func stopPlayers() {
        playerHash.values.forEach { (player) in
            player.stop()
        }
    }

}


// MARK: cache
extension AudioPlayerManager {
    
    typealias DownloadCompletionHandler = (Result<Data, Error>) -> Void
    
    private func createAndRetrieveURLSession() -> URLSession {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.requestCachePolicy = .returnCacheDataElseLoad
        sessionConfiguration.urlCache = cache
        return URLSession(configuration: sessionConfiguration)
    }
    
    private func downloadContent(fromUrlString: String, completionHandler: @escaping DownloadCompletionHandler) {
        
        guard let downloadUrl = URL(string: fromUrlString) else { return }
        let urlRequest = URLRequest(url: downloadUrl)
        // First try to fetching cached data if exist
        if let cachedData = self.cache.cachedResponse(for: urlRequest) {
            print("Cached data in bytes:", cachedData.data)
            completionHandler(.success(cachedData.data))
        } else {
            // No cached data, download content than cache the data
            createAndRetrieveURLSession().dataTask(with: urlRequest) { (data, response, error) in
                
                if let error = error {
                    completionHandler(.failure(error))
                    
                } else {
                    
                    let cachedData = CachedURLResponse(response: response!, data: data!)
                    self.cache.storeCachedResponse(cachedData, for: urlRequest)
                    
                    completionHandler(.success(data!))
                }
                
                }.resume()
        }
    }
}

