//
//  Item.swift
//  Sandbox
//
//  Created by 吉井 大樹 on 2024/08/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
