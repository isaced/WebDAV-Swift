//
//  PlatformTypes.swift
//  WebDAV-Swift
//
//  Created by GitHub Copilot on 2025/7/13.
//

import Foundation

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif
