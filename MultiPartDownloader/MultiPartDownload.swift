//
//  MultiPartDownload.swift
//  FileEncryption
//
//  Created by Neeraj Singh on 3/6/20.
//  Copyright © 2020 Neeraj Singh. All rights reserved.
//

import Foundation
import Cocoa


enum HTTPHeader : String {
    case acceptRanges = "Accept-Ranges"
    case contentLength = "Content-Length"
    case range = "Range"

}

enum HTTPMethod : String {
    case head = "HEAD"
    case get = "GET"
    case post = "POST"
}

enum MultiPartDownloadError: String {
    case headNotSupported
    case rangeNotSupported
    case contentLengthNotSupported
    case partialDownloadFail
    case nilReadFileHandler
    case missingFileSaveLocation
    case cannotWriteIntoSaveLocation
    
    var error: Error {
        var userInfo = [String: String]()
        userInfo[NSLocalizedDescriptionKey] = self.rawValue
        return NSError(domain: MultiPartDownloadError.errorDomain, code: MultiPartDownloadError.errorCode, userInfo: userInfo)
    }

    static let errorDomain = "com.apple.MultiPartDownload.ErrorDomain"
    static let errorCode: Int = 10_000
}


class MultiPartDownload : NSObject, URLSessionDelegate {

    let downloadURL: URL
    private (set) var session: URLSession!
    let chunkSize = 2 * 1024 * 1024 // 1MB
    let callbackQueue = OperationQueue()
    let taskQueue = OperationQueue()

    private var error: Error?
    private var failure: MultiPartDownloadError?
    
    var failureError: Error? {
        if let error = self.error {
            return error
        }
        return self.failure?.error
    }

    init(_ url: URL) {
        downloadURL = url
        let config = URLSession.shared.configuration
        super.init()
        session = URLSession(configuration: config, delegate: self, delegateQueue: callbackQueue)
        callbackQueue.qualityOfService = .background
        callbackQueue.maxConcurrentOperationCount = 1

        taskQueue.qualityOfService = .background
        taskQueue.maxConcurrentOperationCount = 5
    }
    
    func start(completionHandler: @escaping (URL?, Error?) -> Void) {
        headDetails {[weak self] (response, error) in
            guard let strongSelf = self else { return }
            
            guard error == nil else {
                strongSelf.error = error
                completionHandler(nil, error)
                return
            }
            
            guard let response = response else {
                strongSelf.failure = .headNotSupported
                completionHandler(nil, strongSelf.failureError)

                return
            }

            // range is not supported in head call
            guard response.rangeSupported else {
                strongSelf.failure = .rangeNotSupported
                completionHandler(nil, strongSelf.failureError)
                return
            }

            // content length in not supported in head call
            guard let length = response.contentLength else {
                strongSelf.failure = .contentLengthNotSupported
                completionHandler(nil, strongSelf.failureError)
                return
            }

            strongSelf.downloadContent(length, completionHandler: completionHandler)
        }
    }

    private func askForSaveFileLocation(_ title: String, _ fileURL: URL) -> URL? {
        var url = FileManager.default.temporaryDirectory
        url.appendPathComponent("MultiPart")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        url.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        url.appendPathExtension(fileURL.pathExtension)
        return url
    }
    
    private func writeFilehandle(_ path: URL) -> FileHandle? {
        do {
            if !FileManager.default.fileExists(atPath: path.path) {
                if !FileManager.default.createFile(atPath: path.path, contents: nil, attributes: nil) {
                    print("File creation failed")
                }
            }
            let handle = try FileHandle(forWritingTo: path)
            return handle
        } catch {
            self.error = error
        }
        return nil
    }
    
    private func combineDownloadedChunks(_ downloadedChunks: [Int: FileHandle?]) -> URL? {
        let chunks = downloadedChunks.filter { $0.value != nil}
        guard chunks.count > 0, chunks.count == downloadedChunks.count else {
            self.failure = .partialDownloadFail
            return nil
        }
        
        guard let saveURL = askForSaveFileLocation("Save", downloadURL) else {
            self.failure = .missingFileSaveLocation
            return nil
        }
        
        guard let writeFileHandle = writeFilehandle(saveURL) else {
            self.failure = .cannotWriteIntoSaveLocation
            return nil
        }
        
        for index in 0..<downloadedChunks.count {
            guard let optionalHandler = downloadedChunks[index], let readFileHandler = optionalHandler else {
                self.failure = .nilReadFileHandler
                return nil
            }
            let data = readFileHandler.readDataToEndOfFile()
            writeFileHandle.write(data)
        }
        return saveURL
    }
    
    private func downloadContent(_ length: Int, completionHandler: @escaping (URL?, Error?) -> Void) {
        let numberOfChunk = length / chunkSize + (((length % chunkSize) > 0) ? 1 : 0)
        var downloadedChunks = [Int: FileHandle?]()
        var markedFailed = false
        for index in 0..<numberOfChunk {
            if markedFailed { break }
            var request = URLRequest(url: downloadURL)
            request.httpMethod = HTTPMethod.get.rawValue
            request.addValue(range(index, length), forHTTPHeaderField: HTTPHeader.range.rawValue)
            
            let chunkIndex = index
            queueTask(with: request) {[weak self] (url, response, error) in
                guard let strongSelf = self else { return }
                if let error = error {
                    print("\(#function): Error in Index = \(chunkIndex) error: \(error)")
                    strongSelf.error = error
                    markedFailed = true
                }

                if let url = url, let file = try? FileHandle(forReadingFrom: url) {
                    downloadedChunks[chunkIndex] = file
                } else {
                    strongSelf.failure = .partialDownloadFail
                    markedFailed = true
                    downloadedChunks[chunkIndex] = nil
                }
                if downloadedChunks.count == numberOfChunk {
                    completionHandler(strongSelf.combineDownloadedChunks(downloadedChunks), strongSelf.failureError)
                }
            }
        }
    }
    
    private func queueTask(with request: URLRequest, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) {
        taskQueue.addOperation { [weak self] in
            guard let strongSelf = self else { return }
            let sem = DispatchSemaphore(value: 0)
            let task = strongSelf.session.downloadTask(with: request) { (url, response, error) in
                completionHandler(url, response, error)
                sem.signal()
            }
            task.resume()
            sem.wait()
        }
    }
    
    private func range(_ index: Int, _ length : Int  ) -> String {
        let start = index * chunkSize
        let end = start + chunkSize - 1
        var range = "\(start)-\(end)"
        if end > length {
            range = "\(start)-"
        }
        return "bytes=\(range)"
    }

    
    private func headDetails( _ handler: @escaping (_ : HTTPURLResponse?, _ error : Error?) -> Void) {
        var request = URLRequest(url: downloadURL)
        request.httpMethod = HTTPMethod.head.rawValue
        
        let task = session.dataTask(with: request) { (_, response, error) in
            handler(response as? HTTPURLResponse, error)
        }
        task.resume()
    }
}

extension HTTPURLResponse {
    var rangeSupported: Bool {
        guard let acceptRanges = self.allHeaderFields[HTTPHeader.acceptRanges.rawValue] as? String else { return false }
        return acceptRanges.lowercased() == "bytes"
    }
    
    var contentLength: Int? {
        guard let contentLength = self.allHeaderFields[HTTPHeader.contentLength.rawValue] as? String else { return nil }
        return Int(contentLength)
    }
    
    var partialContent: Bool {
        return self.statusCode == 206
    }
}
