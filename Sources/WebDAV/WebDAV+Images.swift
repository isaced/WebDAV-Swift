//
//  WebDAV+Images.swift
//  WebDAV-Swift
//
//  Created by Isaac Lyons on 11/16/20.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

//MARK: ThumbnailProperties

public struct ThumbnailProperties: Hashable {
    private var width: Int?
    private var height: Int?
    
    public var contentMode: ContentMode
    
    public var size: (width: Int, height: Int)? {
        get {
            if let width = width,
               let height = height {
                return (width, height)
            }
            return nil
        }
        set {
            width = newValue?.width
            height = newValue?.height
        }
    }
    
    /// Configurable default thumbnail properties. Initial value of content fill and server default dimensions.
    public static var `default` = ThumbnailProperties(contentMode: .fill)
    /// Content fill with the server's default dimensions.
    public static let fill = ThumbnailProperties(contentMode: .fill)
    /// Content fit with the server's default dimensions.
    public static let fit = ThumbnailProperties(contentMode: .fit)
    
    /// Constants that define how the thumbnail fills the dimensions.
    public enum ContentMode: Hashable {
        case fill
        case fit
    }
    
    /// - Parameters:
    ///   - size: The size of the thumbnail. A nil value will use the server's default dimensions.
    ///   - contentMode: A flag that indicates whether the thumbnail view fits or fills the dimensions.
    public init(_ size: (width: Int, height: Int)? = nil, contentMode: ThumbnailProperties.ContentMode) {
        if let size = size {
            width = size.width
            height = size.height
        }
        self.contentMode = contentMode
    }
    
    /// - Parameters:
    ///   - size: The size of the thumbnail. Width and height will be truncated to integer pixel counts.
    ///   - contentMode: A flag that indicates whether the thumbnail view fits or fills the image of the given dimensions.
    public init(size: CGSize, contentMode: ThumbnailProperties.ContentMode) {
        width = Int(size.width)
        height = Int(size.height)
        self.contentMode = contentMode
    }
}

//MARK: Public

public extension WebDAV {
    
    enum ThumbnailPreviewMode {
        /// Only show a preview thumbnail if there is already one loaded into memory.
        case memoryOnly
        /// Allow the disk cache to be loaded if there are no thumbnails in memory.
        /// Note that this can be an expensive process and is run on the main thread.
        case diskAllowed
        /// Load the specific thumbnail if available, from disk if not in memory.
        case specific(ThumbnailProperties)
    }
    
    //MARK: Images
    
    /// Download and cache an image from the specified file path.
    /// - Parameters:
    ///   - path: The path of the image to download.
    ///   - account: The WebDAV account.
    ///   - password: The WebDAV account's password.
    ///   - options: Options for caching the results. Empty set uses default caching behavior.
    ///   - preview: Behavior for running the completion closure with cached thumbnails before the full-sized image is fetched.
    ///   Note that `.diskAllowed` will load all thumbnails for the given image which can be an expensive process.
    ///   `.memoryOnly` and `.specific()` are recommended unless you do not know what thumbnails exist.
    ///   - completion: If account properties are invalid, this will run immediately on the same thread with an error.
    ///   Otherwise, it will run on a utility thread with a preview (if available and a `preview` mode is provided) with a `.placeholder` error,
    ///   then run on a background thread when the network call finishes.
    ///   This will not be called with the thumbnail after being called with the full-size image.
    ///   - image: The image downloaded, if successful.
    ///   The cached image if it has already been downloaded.
    ///   - cachedImageURL: The URL of the cached image.
    ///   - error: A WebDAVError if the call was unsuccessful. `nil` if it was.
    /// - Returns: The request identifier.
    @discardableResult
    func downloadImage<A: WebDAVAccount>(path: String, account: A, password: String, caching options: WebDAVCachingOptions = [], preview: ThumbnailPreviewMode? = .none, completion: @escaping (_ image: PlatformImage?, _ error: WebDAVError?) -> Void) -> URLSessionDataTask? {
        cachingDataTask(cache: imageCache, path: path, account: account, password: password, caching: options, valueFromData: { PlatformImage(data: $0) }, placeholder: {
            // Load placeholder thumbnail
            var thumbnails = self.getAllMemoryCachedThumbnails(forItemAtPath: path, account: account)?.values
            
            switch preview {
            case .none:
                return nil
            case .specific(let properties):
                return self.getCachedThumbnail(forItemAtPath: path, account: account, with: properties)
            case .memoryOnly:
                break
            case .diskAllowed:
                // Only load from disk if there aren't any in memory
                if thumbnails?.isEmpty ?? true {
                    thumbnails = self.getAllMemoryCachedThumbnails(forItemAtPath: path, account: account)?.values
                }
            }
            let largestThumbnail = thumbnails?.max(by: { $0.size.width * $0.size.height < $1.size.width * $1.size.height })
            return largestThumbnail
        }, completion: completion)
    }
    
    //MARK: Thumbnails
    
    /// Download and cache an image's thumbnail from the specified path.
    ///
    /// Only works with Nextcloud or other instances that use Nextcloud's same thumbnail URL structure.
    /// - Parameters:
    ///   - path: The path of the image to download the thumbnail of.
    ///   - account: The WebDAV account.
    ///   - password: The WebDAV account's password.
    ///   - properties: The properties for how the server should render the thumbnail.
    ///   Default behavior determined by `ThumbnailProperties`'s `default` property.
    ///   - options: Options for caching the results. Empty set uses default caching behavior.
    ///   - completion: If account properties are invalid, this will run immediately on the same thread.
    ///   Otherwise, it runs when the network call finishes on a background thread.
    ///   - image: The thumbnail downloaded, if successful.
    ///   The cached thumbnail if it has already been downloaded.
    ///   - cachedImageURL: The URL of the cached thumbnail.
    ///   - error: A WebDAVError if the call was unsuccessful. `nil` if it was.
    /// - Returns: The request identifier.
    @discardableResult
    func downloadThumbnail<A: WebDAVAccount>(
        path: String, account: A, password: String, with properties: ThumbnailProperties = .default,
        caching options: WebDAVCachingOptions = [], completion: @escaping (_ image: PlatformImage?, _ error: WebDAVError?) -> Void
    ) -> URLSessionDataTask? {
        // This function looks a lot like cachingDataTask and authorizedRequest,
        // but generalizing both of those to support thumbnails would make them
        // so much more complicated that it's better to just have similar code here.
        
        // Check cache
        
        var cachedThumbnail: PlatformImage?
        if !options.contains(.doNotReturnCachedResult) {
            if let thumbnail = getCachedThumbnail(forItemAtPath: path, account: account, with: properties) {
                completion(thumbnail, nil)
                
                if !options.contains(.requestEvenIfCached) {
                    if options.contains(.removeExistingCache) {
                        try? deleteCachedThumbnail(forItemAtPath: path, account: account, with: properties)
                    }
                    return nil
                } else {
                    cachedThumbnail = thumbnail
                }
            }
        }
        
        if options.contains(.removeExistingCache) {
            try? deleteCachedThumbnail(forItemAtPath: path, account: account, with: properties)
        }
        
        // Create Network request
        
        guard let unwrappedAccount = UnwrappedAccount(account: account), let auth = self.auth(username: unwrappedAccount.username, password: password) else {
            completion(nil, .invalidCredentials)
            return nil
        }
        
        guard let url = nextcloudPreviewURL(for: unwrappedAccount.baseURL, at: path, with: properties) else {
            completion(nil, .unsupported)
            return nil
        }
        
        var request = URLRequest(url: url)
        request.addValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        
        // Perform the network request
        
        let task = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil).dataTask(with: request) { [weak self] data, response, error in
            var error = WebDAVError.getError(response: response, error: error)
            
            if let error = error {
                return completion(nil, error)
            } else if let data = data,
                      let thumbnail = PlatformImage(data: data) {
                // Cache result
                if !options.contains(.removeExistingCache),
                   !options.contains(.doNotCacheResult) {
                    // Memory cache
                    self?.saveToMemoryCache(thumbnail: thumbnail, forItemAtPath: path, account: account, with: properties)
                    // Disk cache
                    do {
                        try self?.saveThumbnailToDiskCache(data: data, forItemAtPath: path, account: account, with: properties)
                    } catch let cachingError {
                        error = .nsError(cachingError)
                    }
                }
                
                if thumbnail != cachedThumbnail {
                    completion(thumbnail, error)
                }
            } else {
                completion(nil, nil)
            }
        }
        
        task.resume()
        return task
    }
    
    //MARK: Image Cache
    
    /// Get the cached image for a specified path from the memory cache if available.
    /// Otherwise load it from disk and save to memory cache.
    /// - Parameters:
    ///   - path: The path used to download the image.
    ///   - account: The WebDAV account used to download the image.
    /// - Returns: The cached image if it is available.
    func getCachedImage<A: WebDAVAccount>(forItemAtPath path: String, account: A) -> PlatformImage? {
        getCachedValue(cache: imageCache, forItemAtPath: path, account: account, valueFromData: { PlatformImage(data: $0) })
    }
    
    //MARK: Thumbnail Cache
    
    /// Get the cached thumbnails of the image at the specified path from the memory cache only.
    /// - Parameters:
    ///   - path: The path used to download the thumbnails.
    ///   - account: The WebDAV account used to download the thumbnails.
    /// - Returns: A dictionary of thumbnails with their properties as keys.
    func getAllMemoryCachedThumbnails<A: WebDAVAccount>(forItemAtPath path: String, account: A) -> [ThumbnailProperties: PlatformImage]? {
        getCachedValue(from: thumbnailCache, forItemAtPath: path, account: account)
    }
    
    /// Get all cached thumbnails of the image at the specified path.
    ///
    /// This loads thumbnails from the disk cache and can be
    /// expensive to run if there are many cached thumbnails.
    ///
    /// To get only thumbnails cached in memory, use `getAllMemoryCachedThumbnails`.
    /// - Parameters:
    ///   - path: The path used to download the thumbnails.
    ///   - account: The WebDAV account used to download the thumbnails.
    /// - Returns: A dictionary of thumbnails with their properties as keys.
    /// - Throws: An error if the cached files couldn't be loaded.
    func getAllCachedThumbnails<A: WebDAVAccount>(forItemAtPath path: String, account: A) throws -> [ThumbnailProperties: PlatformImage]? {
        try loadAllCachedThumbnailsFromDisk(forItemAtPath: path, account: account)
    }
    
    /// Get the cached thumbnail of the image at the specified path with the specified properties, if available.
    /// - Parameters:
    ///   - path: The path used to download the thumbnail.
    ///   - account: The WebDAV account used to download the thumbnail.
    ///   - properties: The properties of the thumbnail.
    /// - Returns: The thumbnail if it is available.
    func getCachedThumbnail<A: WebDAVAccount>(forItemAtPath path: String, account: A, with properties: ThumbnailProperties) -> PlatformImage? {
        getAllMemoryCachedThumbnails(forItemAtPath: path, account: account)?[properties] ??
            loadCachedThumbnailFromDisk(forItemAtPath: path, account: account, with: properties)
    }
    
    /// Delete the cached thumbnail of the image at the specified path with the specified properties.
    ///
    /// Deletes cached data from both memory and disk caches.
    /// - Parameters:
    ///   - path: The path used to download the thumbnail.
    ///   - account: The WebDAV account used to download the thumbnail.
    ///   - properties: The properties of the thumbnail.
    /// - Throws: An error if the file couldn't be deleted.
    func deleteCachedThumbnail<A: WebDAVAccount>(forItemAtPath path: String, account: A, with properties: ThumbnailProperties) throws {
        let accountPath = AccountPath(account: account, path: path)
        if var cachedThumbnails = thumbnailCache[accountPath] {
            cachedThumbnails.removeValue(forKey: properties)
            if cachedThumbnails.isEmpty {
                thumbnailCache.removeValue(forKey: accountPath)
            } else {
                thumbnailCache[accountPath] = cachedThumbnails
            }
        }
        
        try deleteCachedThumbnailFromDisk(forItemAtPath: path, account: account, with: properties)
    }
    
    /// Delete the cached thumbnails of the image at the specified path.
    ///
    /// Deletes cached data from both memory and disk caches.
    /// - Parameters:
    ///   - path: The path used to download the thumbnails.
    ///   - account: The WebDAV account used to download the thumbnails.
    /// - Throws: An error if the files couldn't be deleted.
    func deleteAllCachedThumbnails<A: WebDAVAccount>(forItemAtPath path: String, account: A) throws {
        let accountPath = AccountPath(account: account, path: path)
        thumbnailCache.removeValue(forKey: accountPath)
        try deleteAllCachedThumbnailsFromDisk(forItemAtPath: path, account: account)
    }
    
}

//MARK: Internal

extension WebDAV {
    
    //MARK: Pathing
    
    func nextcloudPreviewBaseURL(for baseURL: URL) -> URL? {
        return nextcloudBaseURL(for: baseURL)?
            .appendingPathComponent("index.php")
            .appendingPathComponent("core")
            .appendingPathComponent("preview.png")
    }
    
    func nextcloudPreviewQuery(at path: String, properties: ThumbnailProperties) -> [URLQueryItem]? {
        var path = path
        
        if path.hasPrefix("/") {
            path.removeFirst()
        }
        
        var query = [
            URLQueryItem(name: "file", value: path),
            URLQueryItem(name: "mode", value: "cover")
        ]
        
        if let size = properties.size {
            query.append(URLQueryItem(name: "x", value: "\(size.width)"))
            query.append(URLQueryItem(name: "y", value: "\(size.height)"))
        }
        
        if properties.contentMode == .fill {
            query.append(URLQueryItem(name: "a", value: "1"))
        }
        
        return query
    }
    
    func nextcloudPreviewURL(for baseURL: URL, at path: String, with properties: ThumbnailProperties) -> URL? {
        guard let thumbnailURL = nextcloudPreviewBaseURL(for: baseURL) else { return nil }
        var components = URLComponents(string: thumbnailURL.absoluteString)
        components?.queryItems = nextcloudPreviewQuery(at: path, properties: properties)
        return components?.url
    }
    
    //MARK: Thumbnail Cache
    
    func saveToMemoryCache<A: WebDAVAccount>(thumbnail: PlatformImage, forItemAtPath path: String, account: A, with properties: ThumbnailProperties) {
        let accountPath = AccountPath(account: account, path: path)
        var cachedThumbnails = thumbnailCache[accountPath] ?? [:]
        cachedThumbnails[properties] = thumbnail
        thumbnailCache[accountPath] = cachedThumbnails
    }
    
}
